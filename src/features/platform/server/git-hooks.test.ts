import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

// Each test commits in a fresh clone of the working tree with the real hooks
// installed, so it exercises exactly what a contributor's `git commit` runs.

const repoRoot = join(import.meta.dir, "..", "..", "..", "..");
const timeout = 60_000;

// Synthetic private term; it means nothing.
const term = "Zorblax";

// Git must ignore the caller's config and any GIT_* variables a hook sets.
// Mise shims on PATH must accept the copied mise.toml in the temp directory.
function hookEnv(root: string): Record<string, string> {
	return {
		...Object.fromEntries(
			Object.entries(process.env).filter(
				(entry): entry is [string, string] =>
					!entry[0].startsWith("GIT_") && entry[1] !== undefined,
			),
		),
		GIT_CONFIG_GLOBAL: "/dev/null",
		GIT_CONFIG_NOSYSTEM: "1",
		LANTERNHALL_CONFIG_DIR: join(root, "config"),
		MISE_TRUSTED_CONFIG_PATHS: root,
	};
}

const identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"];

let root: string;
let template: string;
let repo: string;
let env: Record<string, string>;

function run(command: string[], cwd = repo) {
	const result = Bun.spawnSync(command, { cwd, env, stdout: "pipe", stderr: "pipe" });
	return {
		exitCode: result.exitCode,
		output: `${result.stdout.toString()}${result.stderr.toString()}`,
	};
}

function git(args: string[], cwd = repo): string {
	const result = run(["git", ...args], cwd);
	if (result.exitCode !== 0) {
		throw new Error(`git ${args.join(" ")} failed: ${result.output}`);
	}
	return result.output;
}

function commit(message: string) {
	return run(["git", ...identity, "commit", "-m", message]);
}

function head(): string {
	return git(["rev-parse", "HEAD"]).trim();
}

async function stage(path: string, content: string): Promise<void> {
	await mkdir(dirname(join(repo, path)), { recursive: true });
	await writeFile(join(repo, path), content);
	git(["add", "--", path]);
}

/** Built at runtime so this file never holds a token-shaped literal. */
function fakeGithubToken(): string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	const bytes = crypto.getRandomValues(new Uint8Array(36));
	return `ghp_${Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("")}`;
}

beforeAll(async () => {
	root = await mkdtemp(join(tmpdir(), "lanternhall-hooks-"));
	template = join(root, "template");
	env = hookEnv(root);
	await mkdir(join(root, "config"));
	await writeFile(join(root, "config", "denylist.txt"), `${term}\n`);

	// Everything `git add .` would hold: tracked files plus untracked, unignored ones.
	const files = git(["ls-files", "--cached", "--others", "--exclude-standard", "-z"], repoRoot)
		.split("\0")
		.filter((path) => path !== "");
	for (const path of files) {
		await cp(join(repoRoot, path), join(template, path), { recursive: true });
	}
	git(["init", "--quiet", "--initial-branch=main"], template);
	git(["add", "."], template);
	git([...identity, "commit", "--quiet", "--no-verify", "-m", "base"], template);
}, timeout);

afterAll(async () => {
	await rm(root, { recursive: true, force: true });
});

let cloneCount = 0;

beforeEach(async () => {
	cloneCount += 1;
	repo = join(root, `clone-${cloneCount}`);
	git(["clone", "--quiet", template, repo], root);
	await symlink(join(repoRoot, "node_modules"), join(repo, "node_modules"));
	await writeFile(join(repo, ".git", "info", "exclude"), "/node_modules\n");
	// The same script `bun install` runs, so a fresh checkout gets the hooks.
	const install = run([process.execPath, "run", "prepare"]);
	if (install.exitCode !== 0) {
		throw new Error(`bun run prepare failed: ${install.output}`);
	}
});

describe("pre-commit hook", () => {
	test(
		"blocks a commit with a Biome error",
		async () => {
			const before = head();
			await stage("src/bad.ts", "export const value: any = 1;\n");

			const result = commit("feat: add bad");

			expect(result.exitCode).not.toBe(0);
			expect(result.output).toContain("noExplicitAny");
			expect(head()).toBe(before);
		},
		timeout,
	);

	test(
		"blocks a commit with a fake token through gitleaks, without printing the token",
		async () => {
			const before = head();
			const token = fakeGithubToken();
			await stage("src/settings.ts", `export const githubToken = "${token}";\n`);

			const result = commit("feat: add settings");

			expect(result.exitCode).not.toBe(0);
			expect(result.output).toContain("github-pat");
			expect(result.output).not.toContain(token);
			expect(head()).toBe(before);
		},
		timeout,
	);

	test(
		"blocks a commit with a denylist term, without printing the term",
		async () => {
			const before = head();
			await stage("notes.md", `hello\nmeet the ${term} team\n`);

			const result = commit("docs: add notes");

			expect(result.exitCode).not.toBe(0);
			expect(result.output).toContain("notes.md:2");
			expect(result.output.toLowerCase()).not.toContain(term.toLowerCase());
			expect(head()).toBe(before);
		},
		timeout,
	);

	test(
		"passes a clean commit and re-stages Biome fixes",
		async () => {
			const before = head();
			await stage("src/clean.ts", "export const value = {a:1,  b: 'two'}\n");

			const result = commit("feat: add clean");

			expect(result.exitCode).toBe(0);
			expect(git(["rev-parse", "HEAD~1"]).trim()).toBe(before);
			const formatted = 'export const value = { a: 1, b: "two" };\n';
			expect(git(["show", "HEAD:src/clean.ts"])).toBe(formatted);
			expect(git(["status", "--porcelain"])).toBe("");
		},
		timeout,
	);

	test(
		"keeps unstaged edits of a partially staged file out of the commit and in the working tree",
		async () => {
			await stage("src/partial.ts", "export const value = {a:1}\n");
			const unstaged = "export const value = {a:1}\nexport const later = 2;\n";
			await writeFile(join(repo, "src/partial.ts"), unstaged);

			const result = commit("feat: add partial");

			expect(result.exitCode).toBe(0);
			expect(git(["show", "HEAD:src/partial.ts"])).toBe("export const value = { a: 1 };\n");
			expect(await readFile(join(repo, "src/partial.ts"), "utf8")).toContain(
				"export const later = 2;",
			);
		},
		timeout,
	);
});
