import { closeSync, existsSync, openSync, readFileSync } from "node:fs";
import { mkdir, mkdtemp, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { type AddressInfo, createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import type { Subprocess } from "bun";
import { z } from "zod";
import { readTrailbaseConfigTemplate } from "../server/trailbase-config";

// A real TrailBase (the version pinned in mise.toml) for integration tests: temp depot,
// random loopback ports, the repo migrations plus optional test-only ones, never --dev.

const repoRoot = join(import.meta.dir, "..", "..", "..", "..");
const repoMigrations = join(repoRoot, "traildepot", "migrations", "main");

/** The CORS origin the harness allows, matching the default install. */
export const harnessOrigin = "https://lanternhall.localhost:8443";

/** The admin TrailBase creates in every fresh depot. */
export const defaultAdminEmail = "admin@localhost";

/** Prefix of the temp directory holding each harness's depot and log. */
export const harnessDirPrefix = "lanternhall-trailbase-";

const startupTimeoutMs = 15_000;
const stopTimeoutMs = 5_000;

export type TrailbaseHarnessOptions = {
	/** Full config.textproto contents; defaults to the committed template. */
	config?: string;
	/** Directories of test-only migrations, linked into the depot beside the repo migrations. */
	migrationDirs?: readonly string[];
};

export type MintedToken = { authToken: string; csrfToken: string };

export type TrailbaseHarness = {
	/** Public API base URL, such as http://127.0.0.1:52011. */
	publicUrl: string;
	/** Admin UI and admin API base URL. */
	adminUrl: string;
	depot: string;
	pid: number;
	mintToken(email: string): Promise<MintedToken>;
	/**
	 * Stops TrailBase and deletes the depot; safe to call more than once.
	 * Call it in afterAll: `bun test` waits for a running TrailBase, so a missed stop hangs the run.
	 */
	stop(): Promise<void>;
};

const mintOutput = z.object({ auth_token: z.string(), csrf_token: z.string() });

// Holds all probes open together so they get distinct ports, then frees them for TrailBase.
async function freePorts(count: number): Promise<number[]> {
	const servers = Array.from({ length: count }, () => createServer());
	await Promise.all(
		servers.map(
			(server) =>
				new Promise<void>((resolve, reject) => {
					server.once("error", reject);
					server.listen(0, "127.0.0.1", resolve);
				}),
		),
	);
	const ports = servers.map((server) => (server.address() as AddressInfo).port);
	await Promise.all(servers.map((server) => new Promise((resolve) => server.close(resolve))));
	return ports;
}

async function linkMigrations(target: string, extraDirs: readonly string[]): Promise<void> {
	await mkdir(target, { recursive: true });
	// The repo has no migrations directory until its first migration lands.
	const dirs = existsSync(repoMigrations) ? [repoMigrations, ...extraDirs] : extraDirs;
	for (const dir of dirs) {
		for (const name of await readdir(dir)) {
			if (name.endsWith(".sql")) {
				await symlink(resolve(dir, name), join(target, name));
			}
		}
	}
}

function logTail(logPath: string): string {
	return readFileSync(logPath, "utf8").trimEnd().split("\n").slice(-20).join("\n");
}

async function waitUntilHealthy(child: Subprocess, publicUrl: string, logPath: string) {
	const deadline = Date.now() + startupTimeoutMs;
	while (Date.now() < deadline) {
		if (child.exitCode !== null) {
			throw new Error(
				`TrailBase exited with code ${child.exitCode} before it was healthy:\n${logTail(logPath)}`,
			);
		}
		try {
			const response = await fetch(`${publicUrl}/api/healthcheck`, {
				signal: AbortSignal.timeout(1_000),
			});
			if (response.ok) {
				return;
			}
		} catch {
			// Not listening yet.
		}
		await Bun.sleep(50);
	}
	throw new Error(`TrailBase was not healthy within ${startupTimeoutMs} ms:\n${logTail(logPath)}`);
}

async function mint(depot: string, email: string): Promise<MintedToken> {
	const child = Bun.spawn(["trail", "--depot", depot, "user", "mint", email], {
		cwd: repoRoot,
		stdin: "ignore",
		stdout: "pipe",
		stderr: "pipe",
	});
	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(child.stdout).text(),
		new Response(child.stderr).text(),
		child.exited,
	]);
	// stderr repeats the tokens in clear, so it is shown only when minting failed.
	if (exitCode !== 0) {
		throw new Error(`trail user mint ${email} failed (exit ${exitCode}): ${stderr.trim()}`);
	}
	const output = mintOutput.parse(JSON.parse(Buffer.from(stdout.trim(), "base64").toString()));
	return { authToken: output.auth_token, csrfToken: output.csrf_token };
}

export async function startTrailbase(
	options: TrailbaseHarnessOptions = {},
): Promise<TrailbaseHarness> {
	const base = await mkdtemp(join(tmpdir(), harnessDirPrefix));
	const depot = join(base, "depot");
	const logPath = join(base, "trail.log");
	let child: Subprocess | undefined;
	let stopping: Promise<void> | undefined;

	const stop = (): Promise<void> => {
		stopping ??= (async () => {
			if (child !== undefined) {
				child.kill("SIGTERM");
				const exited = await Promise.race([
					child.exited.then(() => true),
					Bun.sleep(stopTimeoutMs).then(() => false),
				]);
				if (!exited) {
					child.kill("SIGKILL");
					await child.exited;
				}
			}
			await rm(base, { recursive: true, force: true });
		})();
		return stopping;
	};

	try {
		await linkMigrations(join(depot, "migrations", "main"), options.migrationDirs ?? []);
		await writeFile(
			join(depot, "config.textproto"),
			options.config ?? (await readTrailbaseConfigTemplate()),
		);
		const [publicPort, adminPort] = await freePorts(2);
		const publicUrl = `http://127.0.0.1:${publicPort}`;
		const adminUrl = `http://127.0.0.1:${adminPort}`;

		const log = openSync(logPath, "w");
		try {
			child = Bun.spawn(
				[
					"trail",
					"--depot",
					depot,
					"run",
					"--address",
					`127.0.0.1:${publicPort}`,
					"--admin-address",
					`127.0.0.1:${adminPort}`,
					"--cors-allowed-origins",
					harnessOrigin,
				],
				{ cwd: repoRoot, stdin: "ignore", stdout: log, stderr: log },
			);
		} finally {
			closeSync(log);
		}
		await waitUntilHealthy(child, publicUrl, logPath);

		return {
			publicUrl,
			adminUrl,
			depot,
			pid: child.pid,
			mintToken: (email) => mint(depot, email),
			stop,
		};
	} catch (error) {
		await stop();
		throw error;
	}
}
