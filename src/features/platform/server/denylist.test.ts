import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseDenylist, runDenylistCheck } from "./denylist";

// Synthetic private terms; none of them means anything.
const term = "Zorblax";

// Git must ignore the caller's config and any GIT_* variables a hook sets,
// so the temp repo behaves the same everywhere.
const env: Record<string, string> = {
	...Object.fromEntries(
		Object.entries(process.env).filter(
			(entry): entry is [string, string] => !entry[0].startsWith("GIT_") && entry[1] !== undefined,
		),
	),
	GIT_CONFIG_GLOBAL: "/dev/null",
	GIT_CONFIG_NOSYSTEM: "1",
};

let root: string;
let repo: string;
let configDir: string;

function git(args: string[], cwd = repo): void {
	const result = Bun.spawnSync(["git", ...args], { cwd, env, stderr: "pipe" });
	if (result.exitCode !== 0) {
		throw new Error(`git ${args.join(" ")} failed: ${result.stderr.toString()}`);
	}
}

async function writeRepoFile(path: string, content: string): Promise<void> {
	await mkdir(join(repo, path, ".."), { recursive: true });
	await writeFile(join(repo, path), content);
}

async function stage(path: string, content: string): Promise<void> {
	await writeRepoFile(path, content);
	git(["add", "--", path]);
}

async function writeDenylist(text: string): Promise<void> {
	await writeFile(join(configDir, "denylist.txt"), text);
}

function check(cwd = repo, overrides: Record<string, string> = {}) {
	return runDenylistCheck({
		cwd,
		env: { ...env, LANTERNHALL_CONFIG_DIR: configDir, ...overrides },
		home: join(root, "home"),
	});
}

beforeEach(async () => {
	root = await mkdtemp(join(tmpdir(), "lanternhall-denylist-"));
	repo = join(root, "repo");
	configDir = join(root, "config");
	await mkdir(repo);
	await mkdir(configDir);
	git(["init", "--quiet", "--initial-branch=main"]);
});

afterEach(async () => {
	await rm(root, { recursive: true, force: true });
});

describe("parseDenylist", () => {
	test("one term per line, trimmed; blank lines and # comments are skipped", () => {
		expect(
			parseDenylist("# private terms\n\n  Zorblax  \r\nQuux Labs\n   # indented comment\n"),
		).toEqual(["Zorblax", "Quux Labs"]);
	});
});

describe("runDenylistCheck", () => {
	test("a staged term fails, naming file and line but never the term", async () => {
		await writeDenylist(`# private\n${term}\n`);
		await stage("notes/a.md", "hello\nmeet the ZORBLAX team\n");

		const result = check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain("notes/a.md:2");
		expect(result.message.toLowerCase()).not.toContain(term.toLowerCase());
	});

	test("every hit is reported, one per line, in path order", async () => {
		await writeDenylist(`${term}\nQuux Labs\n`);
		await stage("b.txt", "quux labs\nclean\nzorblax and QUUX LABS\n");
		await stage("a.txt", "clean\nZorblax\n");
		await stage("c.txt", "clean\n");

		const result = check();

		expect(result.exitCode).toBe(1);
		const hits = result.message.split("\n").slice(1);
		expect(hits).toEqual(["  a.txt:2", "  b.txt:1", "  b.txt:3"]);
	});

	test("scans staged content, not the working tree or untracked files", async () => {
		await writeDenylist(`${term}\n`);

		await stage("clean.txt", "clean\n");
		await writeRepoFile("clean.txt", `now with ${term}\n`);
		await writeRepoFile("untracked.txt", `${term}\n`);
		expect(check().exitCode).toBe(0);

		await stage("dirty.txt", `${term}\n`);
		await writeRepoFile("dirty.txt", "cleaned in the working tree only\n");
		const result = check();
		expect(result.exitCode).toBe(1);
		expect(result.message).toContain("dirty.txt:1");
	});

	test("a term in a staged path fails with the term masked out of the path", async () => {
		await writeDenylist("acme\nacmecorp\n");
		await stage("notes/AcmeCorp-plan.md", "clean\n");

		const result = check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain("notes/********-plan.md (file path)");
		expect(result.message.toLowerCase()).not.toContain("acme");
	});

	test("a staged path and its content are both reported", async () => {
		await writeDenylist(`${term}\n`);
		await stage(`${term}.md`, `${term}\n`);

		const hits = check().message.split("\n").slice(1);

		expect(hits).toEqual(["  *******.md (file path)", "  *******.md:1"]);
	});

	test("a term in the denylist's own path is masked, such as a home directory named after the owner", async () => {
		configDir = join(root, `home-of-${term}`);
		await mkdir(configDir);
		await writeDenylist(`${term}\n`);
		await stage("a.txt", `${term}\n`);

		const result = check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toStartWith(
			`Denylist check failed: staged changes hold terms from ${join(root, "home-of-*******", "denylist.txt")};`,
		);
		expect(result.message.toLowerCase()).not.toContain(term.toLowerCase());
	});

	test("terms match literally, not as patterns", async () => {
		await writeDenylist("a.c\n(x\n");
		await stage("one.txt", "abc\nx\n");
		expect(check().exitCode).toBe(0);

		await stage("two.txt", "a.c\n");
		expect(check().exitCode).toBe(1);
	});

	test("a staged deletion of a file with a term passes", async () => {
		await stage("old.txt", `${term}\n`);
		git([
			"-c",
			"user.name=Test",
			"-c",
			"user.email=test@example.com",
			"commit",
			"--quiet",
			"-m",
			"old",
		]);
		await writeDenylist(`${term}\n`);
		git(["rm", "--quiet", "old.txt"]);

		expect(check().exitCode).toBe(0);
	});

	test("works from a subdirectory of the repo", async () => {
		await writeDenylist(`${term}\n`);
		await stage("sub/dir/file.txt", `${term}\n`);

		const result = check(join(repo, "sub"));

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain("sub/dir/file.txt:1");
	});

	test("clean staged files pass", async () => {
		await writeDenylist(`${term}\n`);
		await stage("a.txt", "clean\n");

		expect(check()).toEqual({ exitCode: 0, message: "Denylist check passed (1 staged file)." });
	});

	test("nothing staged passes", async () => {
		await writeDenylist(`${term}\n`);

		expect(check()).toEqual({ exitCode: 0, message: "Denylist check passed (0 staged files)." });
	});

	test("a comments-only denylist passes", async () => {
		await writeDenylist("# nothing yet\n");
		await stage("a.txt", "# nothing yet\n");

		expect(check().exitCode).toBe(0);
	});

	test("a missing denylist passes with a one-line notice", async () => {
		await stage("a.txt", `${term}\n`);

		const result = check();

		expect(result.exitCode).toBe(0);
		expect(result.message).toBe(
			`Denylist check skipped: ${join(configDir, "denylist.txt")} not found.`,
		);
	});

	test("the denylist defaults to the config dir under the home directory", async () => {
		const defaultConfigDir = join(root, "home", ".config", "lanternhall");
		await mkdir(defaultConfigDir, { recursive: true });
		await writeFile(join(defaultConfigDir, "denylist.txt"), `${term}\n`);
		await stage("a.txt", `${term}\n`);

		expect(check(repo, { LANTERNHALL_CONFIG_DIR: "" }).exitCode).toBe(1);
	});

	test("an unreadable denylist fails instead of passing", async () => {
		await mkdir(join(configDir, "denylist.txt"));

		const result = check();

		expect(result.exitCode).toBe(2);
		expect(result.message).toStartWith(
			`Denylist check failed: cannot read ${join(configDir, "denylist.txt")}:`,
		);
	});

	test("a relative LANTERNHALL_CONFIG_DIR fails", () => {
		const result = check(repo, { LANTERNHALL_CONFIG_DIR: "relative/dir" });

		expect(result).toEqual({
			exitCode: 2,
			message:
				"Denylist check failed: LANTERNHALL_CONFIG_DIR=relative/dir must be an absolute path.",
		});
	});

	test("outside a git repo fails", async () => {
		await writeDenylist(`${term}\n`);
		const outside = join(root, "outside");
		await mkdir(outside);

		const result = check(outside, { GIT_CEILING_DIRECTORIES: root });

		expect(result.exitCode).toBe(2);
		expect(result.message).toStartWith("Denylist check failed: git diff");
	});
});

describe("scripts/check-denylist.ts", () => {
	const script = join(import.meta.dir, "..", "..", "..", "..", "scripts", "check-denylist.ts");

	function run() {
		const result = Bun.spawnSync([process.execPath, script], {
			cwd: repo,
			env: { ...env, LANTERNHALL_CONFIG_DIR: configDir },
			stdout: "pipe",
			stderr: "pipe",
		});
		return {
			exitCode: result.exitCode,
			stdout: result.stdout.toString(),
			stderr: result.stderr.toString(),
		};
	}

	test("blocks a staged term on stderr and keeps the term out of all output", async () => {
		await writeDenylist(`${term}\n`);
		await stage("leak.md", `x\n${term}\n`);

		const { exitCode, stdout, stderr } = run();

		expect(exitCode).toBe(1);
		expect(stdout).toBe("");
		expect(stderr).toContain("leak.md:2");
		expect(`${stdout}${stderr}`.toLowerCase()).not.toContain(term.toLowerCase());
	});

	test("passes with the notice on stdout when there is no denylist", () => {
		const { exitCode, stdout, stderr } = run();

		expect(exitCode).toBe(0);
		expect(stdout).toBe(`Denylist check skipped: ${join(configDir, "denylist.txt")} not found.\n`);
		expect(stderr).toBe("");
	});
});
