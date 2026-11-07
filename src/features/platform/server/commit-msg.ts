export type CommitMessageCheckResult = { exitCode: 0 | 1; message: string };

const types = [
	"feat",
	"fix",
	"perf",
	"refactor",
	"test",
	"docs",
	"build",
	"ci",
	"chore",
	"revert",
] as const;

const scissors = "# ------------------------ >8 ------------------------";

/** Git writes these itself; they are kept as they are rather than rewritten. */
const mergeHeader = /^Merge (branch|branches|remote-tracking branch|tag|commit|pull request) /;

/** `git commit --fixup` and friends; autosquash folds them away before merge. */
const autosquashPrefix = /^(fixup|squash|amend)! /;

/**
 * The message as Git will store it with its default cleanup: nothing from the
 * scissors line down, no comment lines, no trailing whitespace, no leading or
 * trailing blank lines. The hook sees the file before that cleanup runs.
 */
function cleanLines(raw: string): string[] {
	const lines: string[] = [];
	for (const line of raw.split("\n")) {
		if (line === scissors) {
			break;
		}
		if (!line.startsWith("#")) {
			lines.push(line.trimEnd());
		}
	}
	while (lines[0] === "") {
		lines.shift();
	}
	while (lines.at(-1) === "") {
		lines.pop();
	}
	return lines;
}

/** Returns the broken rule, or undefined when the header is valid. */
function headerError(header: string): string | undefined {
	const typeMatch = /^[A-Za-z]+(?=[(!:])/.exec(header);
	if (typeMatch === null) {
		return "header must start with a type";
	}
	const type = typeMatch[0];
	if (!(types as readonly string[]).includes(type)) {
		return `unknown type "${type}"`;
	}
	let rest = header.slice(type.length);
	if (rest.startsWith("(")) {
		const scope = /^\([a-z0-9]+(-[a-z0-9]+)*\)/.exec(rest);
		if (scope === null) {
			return "scope must be lowercase kebab-case, as in (platform)";
		}
		rest = rest.slice(scope[0].length);
	}
	if (rest.startsWith("!")) {
		rest = rest.slice(1);
	}
	if (!rest.startsWith(":")) {
		return 'missing ":" after the type, scope or "!"';
	}
	const subject = rest.slice(1);
	if (subject.trim() === "") {
		return "subject must not be empty";
	}
	if (!/^ \S/.test(subject)) {
		return 'exactly one space after ":"';
	}
	return undefined;
}

function messageError(lines: readonly string[]): string | undefined {
	const [header = "", second] = lines;
	if (second !== undefined && second !== "") {
		return "blank line between the header and the body";
	}
	if (mergeHeader.test(header)) {
		return undefined;
	}
	let target = header;
	while (autosquashPrefix.test(target)) {
		target = target.replace(autosquashPrefix, "");
	}
	return headerError(target);
}

/** Checks a raw commit message file against Conventional Commits. */
export function checkCommitMessage(raw: string): CommitMessageCheckResult {
	const lines = cleanLines(raw);
	if (lines.length === 0) {
		return { exitCode: 1, message: "commit-msg: message is empty" };
	}
	const error = messageError(lines);
	if (error === undefined) {
		return { exitCode: 0, message: "" };
	}
	return {
		exitCode: 1,
		message: [
			`commit-msg: ${error}`,
			`  header:   ${lines[0]}`,
			"  expected: <type>[(scope)][!]: <subject>",
			`  types:    ${types.join(", ")}`,
			"  example:  feat(platform): add release-age check",
		].join("\n"),
	};
}
