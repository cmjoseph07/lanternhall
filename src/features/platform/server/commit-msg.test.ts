import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkCommitMessage } from "./commit-msg";

describe("checkCommitMessage accepts", () => {
	test.each([
		["type and subject", "fix: handle empty config"],
		["scope", "feat(platform): add release-age check"],
		["kebab-case scope", "chore(csuite-scoreboard): rename columns"],
		["breaking marker", "feat!: drop the v1 API"],
		["scope and breaking marker", "refactor(platform)!: rename install config keys"],
		["perf type", "perf: batch reads"],
		["test type", "test: cover empty config"],
		["docs type", "docs: explain setup"],
		["build type", "build: pin bun"],
		["ci type", "ci: add workflow"],
		["revert type", "revert: feat(platform): add release-age check"],
		["trailing newline from -m", "fix: handle empty config\n"],
	])("%s", (_, message) => {
		expect(checkCommitMessage(message)).toEqual({ exitCode: 0, message: "" });
	});

	test("a body and a BREAKING CHANGE footer", () => {
		const message = [
			"feat(platform): move config to TOML",
			"",
			"The JSON loader is gone.",
			"",
			"BREAKING CHANGE: config.json is no longer read.",
			"",
		].join("\n");

		expect(checkCommitMessage(message).exitCode).toBe(0);
	});

	test("comment lines and everything below the scissors line, as the editor leaves them", () => {
		const message = [
			"fix: handle empty config",
			"",
			"# Please enter the commit message for your changes.",
			"# ------------------------ >8 ------------------------",
			"diff --git a/x b/x",
			"not a conventional line",
		].join("\n");

		expect(checkCommitMessage(message).exitCode).toBe(0);
	});

	test.each([
		["merge of a branch", "Merge branch 'main' into feature"],
		["merge of a remote-tracking branch", "Merge remote-tracking branch 'origin/main'"],
		["merge of a tag", "Merge tag 'v0.1.0'"],
		["merge of a pull request", "Merge pull request #12 from someone/branch"],
	])("git's own %s message", (_, message) => {
		expect(checkCommitMessage(message).exitCode).toBe(0);
	});

	test.each([
		["fixup!", "fixup! feat(platform): add release-age check"],
		["squash!", "squash! fix: handle empty config"],
		["amend!", "amend! fix: handle empty config"],
		["nested fixup!", "fixup! fixup! fix: handle empty config"],
	])("%s of a valid header", (_, message) => {
		expect(checkCommitMessage(message).exitCode).toBe(0);
	});
});

describe("checkCommitMessage rejects, naming the rule", () => {
	test.each([
		["no type", "update stuff", "header must start with a type"],
		["unknown type", "feature: add login", 'unknown type "feature"'],
		["uppercase type", "Fix: handle empty config", 'unknown type "Fix"'],
		["empty subject", "fix: ", "subject must not be empty"],
		["whitespace-only subject", "fix:    ", "subject must not be empty"],
		["missing space after colon", "fix:handle empty config", 'exactly one space after ":"'],
		["two spaces after colon", "fix:  handle empty config", 'exactly one space after ":"'],
		["missing colon", "fix(platform) handle empty config", 'missing ":" after the type'],
		["empty scope", "fix(): handle empty config", "scope must be lowercase kebab-case"],
		["scope with space", "fix(my scope): handle", "scope must be lowercase kebab-case"],
		["uppercase scope", "fix(Platform): handle", "scope must be lowercase kebab-case"],
		["unclosed scope", "fix(platform: handle", "scope must be lowercase kebab-case"],
		["empty message", "", "message is empty"],
		["comments only", "# nothing here\n", "message is empty"],
		["fixup! of an invalid header", "fixup! update stuff", "header must start with a type"],
		["revert as git writes it", 'Revert "feat: add login"', "header must start with a type"],
	])("%s", (_, message, rule) => {
		const result = checkCommitMessage(message);

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(rule);
	});

	test("a body not separated from the header by a blank line", () => {
		const result = checkCommitMessage("fix: handle empty config\nmore detail");

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain("blank line between the header and the body");
	});

	test("shows the offending header and the expected format", () => {
		const result = checkCommitMessage("update stuff");

		expect(result.message).toContain("update stuff");
		expect(result.message).toContain("<type>[(scope)][!]: <subject>");
		expect(result.message).toContain(
			"feat, fix, perf, refactor, test, docs, build, ci, chore, revert",
		);
	});
});

describe("scripts/check-commit-msg.ts", () => {
	const repoRoot = join(import.meta.dir, "..", "..", "..", "..");
	const script = join(repoRoot, "scripts", "check-commit-msg.ts");

	function runScript(args: string[], stdin?: string) {
		const result = Bun.spawnSync([process.execPath, script, ...args], {
			cwd: repoRoot,
			stdin: stdin === undefined ? "ignore" : new TextEncoder().encode(stdin),
			stdout: "pipe",
			stderr: "pipe",
		});
		return {
			exitCode: result.exitCode,
			stdout: result.stdout.toString(),
			stderr: result.stderr.toString(),
		};
	}

	async function withMessageFile(content: string, use: (path: string) => void): Promise<void> {
		const dir = await mkdtemp(join(tmpdir(), "lanternhall-commit-msg-"));
		try {
			const path = join(dir, "COMMIT_EDITMSG");
			await writeFile(path, content);
			use(path);
		} finally {
			await rm(dir, { recursive: true, force: true });
		}
	}

	test("passes a valid message file silently", async () => {
		await withMessageFile("fix: handle empty config\n", (path) => {
			const result = runScript([path]);

			expect(result.exitCode).toBe(0);
			expect(result.stdout).toBe("");
			expect(result.stderr).toBe("");
		});
	});

	test("fails an invalid message file with the rule on stderr", async () => {
		await withMessageFile("update stuff\n", (path) => {
			const result = runScript([path]);

			expect(result.exitCode).toBe(1);
			expect(result.stderr).toContain("header must start with a type");
		});
	});

	test("reads stdin when no file is given", () => {
		expect(runScript([], "feat(platform): add check\n").exitCode).toBe(0);
		const invalid = runScript([], "feature: add check\n");
		expect(invalid.exitCode).toBe(1);
		expect(invalid.stderr).toContain('unknown type "feature"');
	});

	test("exits 2 when the message file cannot be read", () => {
		const result = runScript([join(tmpdir(), "lanternhall-no-such-file")]);

		expect(result.exitCode).toBe(2);
		expect(result.stderr).toContain("cannot read");
	});
});
