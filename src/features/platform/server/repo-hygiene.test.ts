import { describe, expect, test } from "bun:test";

// Paths that must never reach git: build scaffolding, local install config,
// secrets, databases, backups and generated output.
const forbidden: ReadonlyArray<{ reason: string; pattern: RegExp }> = [
	{ reason: "scaffolding", pattern: /^SPEC(-[^/]+)?\.md$/ },
	{ reason: "scaffolding", pattern: /^(tasks|docs)\// },
	{ reason: "install config", pattern: /(^|\/)(config|secrets)\.toml$/ },
	{ reason: "install config", pattern: /(^|\/)denylist\.txt$/ },
	{ reason: "secret", pattern: /(^|\/)\.env(\..+)?$/ },
	{ reason: "secret", pattern: /\.(pem|key|p12|pfx)$/ },
	{ reason: "database", pattern: /\.(sqlite|sqlite3|db)(-(wal|shm|journal))?$/ },
	{ reason: "backup", pattern: /(^|\/)backups?\// },
	{ reason: "backup", pattern: /\.(bak|backup)$/ },
	{ reason: "generated", pattern: /(^|\/)(node_modules|coverage|build|\.svelte-kit)\// },
	{ reason: "generated", pattern: /\.bun-build$/ },
];

function git(args: string[], cwd: string): string {
	const result = Bun.spawnSync(["git", ...args], { cwd, stderr: "pipe" });
	if (result.exitCode !== 0) {
		throw new Error(`git ${args.join(" ")} failed: ${result.stderr.toString()}`);
	}
	return result.stdout.toString();
}

const repoRoot = git(["rev-parse", "--show-toplevel"], import.meta.dir).trim();

/**
 * Tracked files plus every untracked file `git add .` would pick up, so a
 * leak is caught whether it is already committed or about to be.
 */
function pathsGitWouldHold(): string[] {
	return git(["ls-files", "--cached", "--others", "--exclude-standard", "-z"], repoRoot)
		.split("\0")
		.filter((path) => path !== "");
}

describe("repo hygiene", () => {
	test("git would hold no scaffolding, config, secret, database, backup or generated path", () => {
		const leaks = pathsGitWouldHold().flatMap((path) =>
			forbidden
				.filter(({ pattern }) => pattern.test(path))
				.map(({ reason }) => `${reason}: ${path}`),
		);
		expect(leaks).toEqual([]);
	});

	test("the committed install config example is allowed", () => {
		const blocked = forbidden.some(({ pattern }) => pattern.test("config.example.toml"));
		expect(blocked).toBe(false);
	});
});
