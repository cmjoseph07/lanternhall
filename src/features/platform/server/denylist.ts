import { readFileSync } from "node:fs";
import { join } from "node:path";
import { resolveInstallPaths } from "../shared/install-config";

export type DenylistCheckResult = { exitCode: 0 | 1 | 2; message: string };

type StagedFile = { path: string; content: string };

/** One term per line, trimmed; blank lines and `#` comments are skipped. */
export function parseDenylist(text: string): string[] {
	return text
		.split("\n")
		.map((line) => line.trim())
		.filter((line) => line !== "" && !line.startsWith("#"));
}

function escapeRegExp(text: string): string {
	return text.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
}

/**
 * Longest terms first, so a term that contains a shorter one is masked whole.
 * `search` ignores the global flag's lastIndex, so one pattern serves both uses.
 */
function termPattern(terms: readonly string[]): RegExp {
	const alternatives = [...terms].sort((a, b) => b.length - a.length).map(escapeRegExp);
	return new RegExp(alternatives.join("|"), "giu");
}

function mask(text: string, pattern: RegExp): string {
	return text.replace(pattern, (match) => "*".repeat(match.length));
}

function findHits(files: readonly StagedFile[], pattern: RegExp): string[] {
	const hits: string[] = [];
	for (const file of files) {
		if (file.path.search(pattern) !== -1) {
			hits.push(`${file.path} (file path)`);
		}
		file.content.split("\n").forEach((line, index) => {
			if (line.search(pattern) !== -1) {
				hits.push(`${file.path}:${index + 1}`);
			}
		});
	}
	return hits;
}

function git(args: string[], cwd: string, env: Record<string, string | undefined>): Uint8Array {
	const result = Bun.spawnSync(["git", ...args], { cwd, env, stderr: "pipe" });
	if (result.exitCode !== 0) {
		throw new Error(`git ${args[0]}: ${result.stderr.toString().trim()}`);
	}
	return result.stdout;
}

/**
 * Reads blobs from the index, not the working tree, so the check sees exactly
 * what the commit will hold. Deletions are skipped; they cannot add a term.
 */
function readStagedFiles(cwd: string, env: Record<string, string | undefined>): StagedFile[] {
	const decoder = new TextDecoder();
	const names = decoder
		.decode(git(["diff", "--cached", "--name-only", "-z", "--diff-filter=ACMRT"], cwd, env))
		.split("\0")
		.filter((path) => path !== "")
		.sort();
	return names.map((path) => ({
		path,
		content: decoder.decode(git(["cat-file", "blob", `:${path}`], cwd, env)),
	}));
}

function messageOf(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

type DenylistRead =
	| { kind: "found"; text: string }
	| { kind: "missing" }
	| { kind: "unreadable"; reason: string };

function readDenylist(path: string): DenylistRead {
	try {
		return { kind: "found", text: readFileSync(path, "utf8") };
	} catch (error) {
		if (error instanceof Error && "code" in error && error.code === "ENOENT") {
			return { kind: "missing" };
		}
		return { kind: "unreadable", reason: messageOf(error) };
	}
}

function checkStaged(
	cwd: string,
	env: Record<string, string | undefined>,
	denylistPath: string,
	pattern: RegExp | null,
): DenylistCheckResult {
	let files: StagedFile[];
	try {
		files = readStagedFiles(cwd, env);
	} catch (error) {
		return { exitCode: 2, message: `Denylist check failed: ${messageOf(error)}` };
	}
	const hits = pattern === null ? [] : findHits(files, pattern);
	if (hits.length > 0) {
		return {
			exitCode: 1,
			message: [
				`Denylist check failed: staged changes hold terms from ${denylistPath}; remove them and stage again.`,
				...hits.map((hit) => `  ${hit}`),
			].join("\n"),
		};
	}
	const count = `${files.length} staged file${files.length === 1 ? "" : "s"}`;
	return { exitCode: 0, message: `Denylist check passed (${count}).` };
}

/**
 * Blocks staged content holding a term from `<config dir>/denylist.txt`.
 * A missing denylist passes with a notice, so forks and CI work without one.
 * Every term is masked out of the message, including from paths such as a
 * home directory named after the owner, so the output never holds a term.
 */
export function runDenylistCheck(options: {
	cwd: string;
	env: Record<string, string | undefined>;
	home: string;
}): DenylistCheckResult {
	const paths = resolveInstallPaths(options.env, options.home);
	if (!paths.ok) {
		return {
			exitCode: 2,
			message: `Denylist check failed: ${paths.variable}=${paths.value} ${paths.reason}.`,
		};
	}
	const denylistPath = join(paths.paths.configDir, "denylist.txt");

	const denylist = readDenylist(denylistPath);
	if (denylist.kind === "missing") {
		return { exitCode: 0, message: `Denylist check skipped: ${denylistPath} not found.` };
	}
	if (denylist.kind === "unreadable") {
		return {
			exitCode: 2,
			message: `Denylist check failed: cannot read ${denylistPath}: ${denylist.reason}`,
		};
	}

	const terms = parseDenylist(denylist.text);
	const pattern = terms.length === 0 ? null : termPattern(terms);
	const result = checkStaged(options.cwd, options.env, denylistPath, pattern);
	return pattern === null ? result : { ...result, message: mask(result.message, pattern) };
}
