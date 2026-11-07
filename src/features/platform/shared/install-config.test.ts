import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import { platformModule } from "../module";
import {
	formatInstallConfigError,
	type InstallConfigResult,
	installConfigSchema,
	loadInstallConfig,
	parseInstallConfig,
	resolveInstallPaths,
} from "./install-config";
import type { ModuleManifest } from "./module-graph";

const path = "/home/someone/.config/lanternhall/config.toml";

const library: ModuleManifest = {
	id: "library",
	kind: "optional",
	dependsOn: [],
	integratesWith: [],
};
const reader: ModuleManifest = {
	id: "reader",
	kind: "optional",
	dependsOn: ["library"],
	integratesWith: [],
};
const manifests = [platformModule, library, reader];

function configText({
	enabled = "[]",
	httpsPort = "8443",
	extra = "",
}: {
	enabled?: string;
	httpsPort?: string;
	extra?: string;
} = {}): string {
	return `
profile = "personal"
owner_email = "owner@example.com"
timezone = "America/Chicago"
week_starts_on = "monday"
${extra}
[modules]
enabled = ${enabled}

[network]
hostname = "lanternhall.localhost"
https_port = ${httpsPort}
trailbase_port = 4000
trailbase_admin_port = 4001
service_port = 4100
valkey_port = 6379
`;
}

function issuesOf(result: InstallConfigResult): Array<{ key: string; reason: string }> {
	if (result.ok || result.error.kind !== "invalid") {
		throw new Error(`expected an invalid-config result, got ${JSON.stringify(result)}`);
	}
	return result.error.issues;
}

describe("resolveInstallPaths", () => {
	test("defaults live under the home directory, outside the repo", () => {
		expect(resolveInstallPaths({}, "/home/someone")).toEqual({
			ok: true,
			paths: {
				configDir: "/home/someone/.config/lanternhall",
				configFile: "/home/someone/.config/lanternhall/config.toml",
				dataDir: "/home/someone/.local/share/lanternhall",
			},
		});
	});

	test("LANTERNHALL_CONFIG_DIR and LANTERNHALL_DATA_DIR override the defaults", () => {
		const env = { LANTERNHALL_CONFIG_DIR: "/tmp/cfg", LANTERNHALL_DATA_DIR: "/tmp/data" };
		expect(resolveInstallPaths(env, "/home/someone")).toEqual({
			ok: true,
			paths: { configDir: "/tmp/cfg", configFile: "/tmp/cfg/config.toml", dataDir: "/tmp/data" },
		});
	});

	test("an empty override counts as unset", () => {
		const result = resolveInstallPaths({ LANTERNHALL_CONFIG_DIR: "" }, "/home/someone");
		expect(result.ok && result.paths.configDir).toBe("/home/someone/.config/lanternhall");
	});

	test("a relative override is an error naming the variable, since it would depend on the cwd", () => {
		expect(resolveInstallPaths({ LANTERNHALL_DATA_DIR: "data" }, "/home/someone")).toEqual({
			ok: false,
			variable: "LANTERNHALL_DATA_DIR",
			value: "data",
			reason: "must be an absolute path",
		});
	});
});

describe("parseInstallConfig", () => {
	test("a valid file yields the typed config", () => {
		const result = parseInstallConfig(
			configText({ enabled: '["library", "reader"]' }),
			path,
			manifests,
		);
		expect(result).toEqual({
			ok: true,
			config: {
				profile: "personal",
				owner_email: "owner@example.com",
				timezone: "America/Chicago",
				week_starts_on: "monday",
				modules: { enabled: ["library", "reader"] },
				network: {
					hostname: "lanternhall.localhost",
					https_port: 8443,
					trailbase_port: 4000,
					trailbase_admin_port: 4001,
					service_port: 4100,
					valkey_port: 6379,
				},
			},
		});
	});

	test("a wrong value names the key and the reason", () => {
		const issues = issuesOf(
			parseInstallConfig(configText({ httpsPort: '"8443"' }), path, manifests),
		);
		expect(issues).toEqual([
			{ key: "network.https_port", reason: "Invalid input: expected number, received string" },
		]);
	});

	test("a port out of range is rejected", () => {
		const issues = issuesOf(
			parseInstallConfig(configText({ httpsPort: "70000" }), path, manifests),
		);
		expect(issues.map((issue) => issue.key)).toEqual(["network.https_port"]);
	});

	test("a missing key is named", () => {
		const text = configText().replace('timezone = "America/Chicago"\n', "");
		expect(issuesOf(parseInstallConfig(text, path, manifests))).toEqual([
			{ key: "timezone", reason: "Invalid input: expected string, received undefined" },
		]);
	});

	test("an unknown key is named, so typos never pass silently", () => {
		const issues = issuesOf(
			parseInstallConfig(configText({ extra: 'time_zone = "UTC"' }), path, manifests),
		);
		expect(issues).toEqual([{ key: "time_zone", reason: "unknown key" }]);
	});

	test("an unknown key inside a table is named with its table", () => {
		const text = configText().replace("[network]\n", "[network]\nhttp_port = 80\n");
		expect(issuesOf(parseInstallConfig(text, path, manifests))).toEqual([
			{ key: "network.http_port", reason: "unknown key" },
		]);
	});

	test("an invalid email, time zone and week start are each named", () => {
		const text = configText()
			.replace("owner@example.com", "not-an-email")
			.replace("America/Chicago", "Mars/Olympus")
			.replace('"monday"', '"funday"');
		expect(issuesOf(parseInstallConfig(text, path, manifests)).map((issue) => issue.key)).toEqual([
			"owner_email",
			"timezone",
			"week_starts_on",
		]);
	});

	test("the hostname must be a .localhost name, which browsers resolve to loopback", () => {
		const text = configText().replace("lanternhall.localhost", "lanternhall.example.com");
		expect(issuesOf(parseInstallConfig(text, path, manifests))).toEqual([
			{
				key: "network.hostname",
				reason:
					"must be localhost or a lowercase name ending in .localhost, so browsers resolve it to loopback",
			},
		]);
	});

	test("two services on one port are rejected", () => {
		const issues = issuesOf(parseInstallConfig(configText({ httpsPort: "4100" }), path, manifests));
		expect(issues).toEqual([
			{ key: "network.service_port", reason: "port 4100 is also used by network.https_port" },
		]);
	});

	test("an optional module enabled without its dependencies is an issue on modules.enabled", () => {
		const issues = issuesOf(
			parseInstallConfig(configText({ enabled: '["reader", "typo"]' }), path, manifests),
		);
		expect(issues).toEqual([
			{ key: "modules.enabled", reason: '"reader" needs "library" enabled too' },
			{ key: "modules.enabled", reason: 'unknown module "typo"' },
		]);
	});

	test("malformed TOML is reported with the path, never thrown", () => {
		const result = parseInstallConfig("profile = ", path, manifests);
		expect(result.ok).toBe(false);
		if (!result.ok) {
			expect(result.error.kind).toBe("invalid-toml");
			expect(result.error.path).toBe(path);
		}
	});
});

describe("loadInstallConfig", () => {
	let dir = "";

	beforeAll(async () => {
		dir = await mkdtemp(join(tmpdir(), "lanternhall-config-"));
	});

	afterAll(async () => {
		await rm(dir, { recursive: true, force: true });
	});

	test("reads and validates the file", async () => {
		const file = join(dir, "config.toml");
		await Bun.write(file, configText());
		const result = await loadInstallConfig(file, manifests);
		expect(result.ok && result.config.network.https_port).toBe(8443);
	});

	test("a missing file is reported, never thrown", async () => {
		const file = join(dir, "absent.toml");
		expect(await loadInstallConfig(file, manifests)).toEqual({
			ok: false,
			error: { kind: "not-found", path: file },
		});
	});

	test("an unreadable path is reported with the reason, never thrown", async () => {
		const file = join(dir, "is-a-directory.toml");
		await mkdir(file);
		const result = await loadInstallConfig(file, manifests);
		expect(result.ok).toBe(false);
		if (!result.ok) {
			expect(result.error.kind).toBe("unreadable");
			expect(result.error.path).toBe(file);
		}
	});
});

describe("formatInstallConfigError", () => {
	test("an invalid config names the file path, the key and the reason on each line", () => {
		const result = parseInstallConfig(configText({ httpsPort: '"8443"' }), path, manifests);
		expect(result.ok).toBe(false);
		if (!result.ok) {
			expect(formatInstallConfigError(result.error)).toBe(
				`Invalid install config ${path}:\n  network.https_port: Invalid input: expected number, received string`,
			);
		}
	});

	test("a missing file names the path", () => {
		expect(formatInstallConfigError({ kind: "not-found", path })).toBe(
			`Install config not found: ${path}`,
		);
	});

	test("unreadable and malformed files name the path and the reason", () => {
		expect(formatInstallConfigError({ kind: "unreadable", path, reason: "EACCES" })).toBe(
			`Cannot read install config ${path}: EACCES`,
		);
		expect(formatInstallConfigError({ kind: "invalid-toml", path, reason: "bad" })).toBe(
			`Install config ${path} is not valid TOML: bad`,
		);
	});
});

describe("config.example.toml", () => {
	const examplePath = join(import.meta.dir, "../../../../config.example.toml");

	test("validates and enables no optional modules", async () => {
		const result = await loadInstallConfig(examplePath, [platformModule]);
		expect(result.ok && result.config.modules.enabled).toEqual([]);
	});

	test("documents every schema key, and no others", async () => {
		const example = Bun.TOML.parse(await Bun.file(examplePath).text());
		expect(keysOfValue(example)).toEqual(keysOfSchema(installConfigSchema));
	});
});

function keysOfSchema(schema: z.ZodType, prefix = ""): string[] {
	if (!(schema instanceof z.ZodObject)) {
		return [prefix];
	}
	return Object.entries(schema.shape)
		.flatMap(([key, child]) => keysOfSchema(child, prefix === "" ? key : `${prefix}.${key}`))
		.sort();
}

function keysOfValue(value: unknown, prefix = ""): string[] {
	if (typeof value !== "object" || value === null || Array.isArray(value)) {
		return [prefix];
	}
	return Object.entries(value)
		.flatMap(([key, child]) => keysOfValue(child, prefix === "" ? key : `${prefix}.${key}`))
		.sort();
}
