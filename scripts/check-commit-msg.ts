import { checkCommitMessage } from "../src/features/platform/server/commit-msg";

// Git's commit-msg hook passes the message file; CI pipes a message on stdin.
const path = process.argv[2];
let raw: string;
try {
	raw = path === undefined ? await Bun.stdin.text() : await Bun.file(path).text();
} catch (error) {
	console.error(
		`commit-msg: cannot read ${path ?? "stdin"}: ${error instanceof Error ? error.message : error}`,
	);
	process.exit(2);
}
const result = checkCommitMessage(raw);
if (result.exitCode !== 0) {
	console.error(result.message);
}
process.exitCode = result.exitCode;
