import { isAbsolute, join } from "node:path";
import { z } from "zod";
import { describeModuleGraphError, type ModuleManifest, validateModuleGraph } from "./module-graph";

const port = z.int().min(1).max(65535);

function isTimeZone(value: string): boolean {
	try {
		new Intl.DateTimeFormat("en-US", { timeZone: value });
		return true;
	} catch {
		return false;
	}
}

const network = z
	.strictObject({
		hostname: z
			.string()
			.regex(
				/^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)*localhost$/,
				"must be localhost or a lowercase name ending in .localhost, so browsers resolve it to loopback",
			),
		https_port: port,
		trailbase_port: port,
		trailbase_admin_port: port,
		service_port: port,
		valkey_port: port,
	})
	.superRefine((value, context) => {
		const seen = new Map<number, string>();
		for (const [key, used] of Object.entries(value)) {
			if (typeof used !== "number") {
				continue;
			}
			const first = seen.get(used);
			if (first === undefined) {
				seen.set(used, key);
			} else {
				context.addIssue({
					code: "custom",
					path: [key],
					message: `port ${used} is also used by network.${first}`,
				});
			}
		}
	});

/** Schema of `config.toml`; keys mirror the file, so they stay snake_case. */
export const installConfigSchema = z.strictObject({
	profile: z.string().min(1),
	owner_email: z.email(),
	timezone: z.string().refine(isTimeZone, "must be an IANA time zone, such as America/Chicago"),
	week_starts_on: z.enum([
		"monday",
		"tuesday",
		"wednesday",
		"thursday",
		"friday",
		"saturday",
		"sunday",
	]),
	modules: z.strictObject({
		enabled: z.array(z.string()),
	}),
	network,
});

export type InstallConfig = z.infer<typeof installConfigSchema>;

export type InstallConfigIssue = { key: string; reason: string };

export type InstallConfigError =
	| { kind: "not-found"; path: string }
	| { kind: "unreadable"; path: string; reason: string }
	| { kind: "invalid-toml"; path: string; reason: string }
	| { kind: "invalid"; path: string; issues: InstallConfigIssue[] };

export type InstallConfigResult =
	| { ok: true; config: InstallConfig }
	| { ok: false; error: InstallConfigError };

export type InstallPaths = { configDir: string; configFile: string; dataDir: string };

export type InstallPathsResult =
	| { ok: true; paths: InstallPaths }
	| { ok: false; variable: string; value: string; reason: string };

/** Install config and data live outside the repo, so git can never pick them up. */
export function resolveInstallPaths(
	env: Readonly<Record<string, string | undefined>>,
	home: string,
): InstallPathsResult {
	const dirs = {
		LANTERNHALL_CONFIG_DIR: join(home, ".config", "lanternhall"),
		LANTERNHALL_DATA_DIR: join(home, ".local", "share", "lanternhall"),
	};
	for (const variable of Object.keys(dirs) as Array<keyof typeof dirs>) {
		const value = env[variable];
		if (value === undefined || value === "") {
			continue;
		}
		// A relative path would resolve against whatever directory a script runs from.
		if (!isAbsolute(value)) {
			return { ok: false, variable, value, reason: "must be an absolute path" };
		}
		dirs[variable] = value;
	}
	return {
		ok: true,
		paths: {
			configDir: dirs.LANTERNHALL_CONFIG_DIR,
			configFile: join(dirs.LANTERNHALL_CONFIG_DIR, "config.toml"),
			dataDir: dirs.LANTERNHALL_DATA_DIR,
		},
	};
}

function messageOf(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function keyOf(path: readonly PropertyKey[]): string {
	return path.map(String).join(".");
}

function issuesOf(error: z.ZodError): InstallConfigIssue[] {
	return error.issues.flatMap((issue) =>
		issue.code === "unrecognized_keys"
			? issue.keys.map((key) => ({ key: keyOf([...issue.path, key]), reason: "unknown key" }))
			: [{ key: keyOf(issue.path), reason: issue.message }],
	);
}

/** Validates config text and the enabled modules' dependencies; never throws for bad input. */
export function parseInstallConfig(
	text: string,
	path: string,
	manifests: readonly ModuleManifest[],
): InstallConfigResult {
	let raw: unknown;
	try {
		raw = Bun.TOML.parse(text);
	} catch (error) {
		return { ok: false, error: { kind: "invalid-toml", path, reason: messageOf(error) } };
	}

	const parsed = installConfigSchema.safeParse(raw);
	if (!parsed.success) {
		return { ok: false, error: { kind: "invalid", path, issues: issuesOf(parsed.error) } };
	}

	const graphErrors = validateModuleGraph(parsed.data.modules.enabled, manifests);
	if (graphErrors.length > 0) {
		const issues = graphErrors.map((error) => ({
			key: "modules.enabled",
			reason: describeModuleGraphError(error),
		}));
		return { ok: false, error: { kind: "invalid", path, issues } };
	}

	return { ok: true, config: parsed.data };
}

export async function loadInstallConfig(
	path: string,
	manifests: readonly ModuleManifest[],
): Promise<InstallConfigResult> {
	let text: string;
	try {
		text = await Bun.file(path).text();
	} catch (error) {
		if (error instanceof Error && "code" in error && error.code === "ENOENT") {
			return { ok: false, error: { kind: "not-found", path } };
		}
		return { ok: false, error: { kind: "unreadable", path, reason: messageOf(error) } };
	}
	return parseInstallConfig(text, path, manifests);
}

export function formatInstallConfigError(error: InstallConfigError): string {
	switch (error.kind) {
		case "not-found":
			return `Install config not found: ${error.path}`;
		case "unreadable":
			return `Cannot read install config ${error.path}: ${error.reason}`;
		case "invalid-toml":
			return `Install config ${error.path} is not valid TOML: ${error.reason}`;
		case "invalid":
			return [
				`Invalid install config ${error.path}:`,
				...error.issues.map((issue) => `  ${issue.key}: ${issue.reason}`),
			].join("\n");
	}
}
