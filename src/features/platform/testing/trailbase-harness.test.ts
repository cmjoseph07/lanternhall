import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readTrailbaseConfigTemplate } from "../server/trailbase-config";
import {
	defaultAdminEmail,
	harnessDirPrefix,
	harnessOrigin,
	startTrailbase,
	type TrailbaseHarness,
} from "./trailbase-harness";

const timeout = 30_000;

// A test-only table and record API, so the auth checks hit a real record API.
const probeMigration = `CREATE TABLE probe (
	id BLOB PRIMARY KEY NOT NULL CHECK(is_uuid_v7(id)) DEFAULT (uuid_v7()),
	note TEXT NOT NULL DEFAULT ''
) STRICT;
`;
const probeApi = `
record_apis: [{
	name: "probe"
	table_name: "probe"
	acl_authenticated: [CREATE, READ]
	enable_subscriptions: true
}]
`;

function isAlive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

async function harnessDirs(): Promise<string[]> {
	return (await readdir(tmpdir())).filter((name) => name.startsWith(harnessDirPrefix)).sort();
}

// Every TCP socket the process listens on, as reported by lsof ("127.0.0.1:4000").
function listeningSockets(pid: number): string[] {
	const result = Bun.spawnSync(
		["lsof", "-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"],
		{ stdout: "pipe", stderr: "pipe" },
	);
	return result.stdout
		.toString()
		.split("\n")
		.filter((line) => line.startsWith("n"))
		.map((line) => line.slice(1))
		.sort();
}

let fixtures: string;
let trailbase: TrailbaseHarness;

beforeAll(async () => {
	fixtures = await mkdtemp(join(tmpdir(), "lanternhall-harness-test-"));
	await writeFile(join(fixtures, "U1700000000__probe.sql"), probeMigration);
	trailbase = await startTrailbase({
		config: `${await readTrailbaseConfigTemplate()}${probeApi}`,
		migrationDirs: [fixtures],
	});
}, timeout);

afterAll(async () => {
	await trailbase?.stop();
	await rm(fixtures, { recursive: true, force: true });
});

describe("TrailBase harness", () => {
	test("serves the health check (AC7)", async () => {
		const response = await fetch(`${trailbase.publicUrl}/api/healthcheck`);
		expect(response.status).toBe(200);
		expect(await response.text()).toBe("Ok");
	});

	test("sends no CORS allow header to a foreign origin (AC5)", async () => {
		const foreign = await fetch(`${trailbase.publicUrl}/api/healthcheck`, {
			headers: { Origin: "https://evil.example" },
		});
		const own = await fetch(`${trailbase.publicUrl}/api/healthcheck`, {
			headers: { Origin: harnessOrigin },
		});
		expect(foreign.headers.get("access-control-allow-origin")).toBeNull();
		expect(own.headers.get("access-control-allow-origin")).toBe(harnessOrigin);
	});

	test("rejects record API calls without a token (AC6)", async () => {
		const url = `${trailbase.publicUrl}/api/records/v1/probe`;
		const list = await fetch(url);
		const create = await fetch(url, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ note: "anonymous" }),
		});
		expect(list.status).toBe(403);
		expect(create.status).toBe(403);

		const { authToken } = await trailbase.mintToken(defaultAdminEmail);
		const authorized = await fetch(url, { headers: { Authorization: `Bearer ${authToken}` } });
		expect(authorized.status).toBe(200);
		expect(await authorized.json()).toEqual({ total_count: 0, records: [] });
	});

	test("does not serve the admin UI or admin API on the public port (AC6)", async () => {
		expect((await fetch(`${trailbase.publicUrl}/_/admin/`)).status).toBe(404);
		expect((await fetch(`${trailbase.publicUrl}/api/_admin/config`)).status).toBe(404);
		expect((await fetch(`${trailbase.adminUrl}/_/admin/`)).status).toBe(200);
	});

	test("listens on loopback sockets only (AC4)", () => {
		const sockets = listeningSockets(trailbase.pid);
		expect(sockets).toEqual(
			[new URL(trailbase.publicUrl).host, new URL(trailbase.adminUrl).host].sort(),
		);
		expect(sockets.every((socket) => socket.startsWith("127.0.0.1:"))).toBe(true);
	});

	test("mints a token whose CSRF token works on the admin API", async () => {
		const { authToken, csrfToken } = await trailbase.mintToken(defaultAdminEmail);
		const response = await fetch(`${trailbase.adminUrl}/api/_admin/config`, {
			headers: { Authorization: `Bearer ${authToken}`, "CSRF-Token": csrfToken },
		});
		expect(response.status).toBe(200);
	});

	test("fails to mint a token for an unknown user", async () => {
		await expect(trailbase.mintToken("nobody@example.com")).rejects.toThrow(
			"trail user mint nobody@example.com failed",
		);
	});

	test(
		"stops the process and removes the depot",
		async () => {
			const other = await startTrailbase();
			await other.stop();
			await other.stop();
			expect(isAlive(other.pid)).toBe(false);
			expect(existsSync(other.depot)).toBe(false);
		},
		timeout,
	);

	test(
		"fails with TrailBase's log when it cannot start, and cleans up",
		async () => {
			const before = await harnessDirs();
			const broken = startTrailbase({ config: "server { no_such_field: 1 }" });
			await expect(broken).rejects.toThrow(/TrailBase exited with code \d+ before it was healthy/);
			await expect(broken).rejects.toThrow("no_such_field");
			expect(await harnessDirs()).toEqual(before);
		},
		timeout,
	);
});
