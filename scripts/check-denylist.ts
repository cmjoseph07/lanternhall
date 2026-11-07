import { homedir } from "node:os";
import { runDenylistCheck } from "../src/features/platform/server/denylist";

const result = runDenylistCheck({ cwd: process.cwd(), env: process.env, home: homedir() });
if (result.exitCode === 0) {
	console.log(result.message);
} else {
	console.error(result.message);
}
process.exitCode = result.exitCode;
