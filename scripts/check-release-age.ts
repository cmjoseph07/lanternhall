import { defaultRegistries, runReleaseAgeCheck } from "../src/features/platform/server/release-age";

const result = await runReleaseAgeCheck({
	cwd: process.cwd(),
	now: new Date(),
	registries: defaultRegistries,
	githubToken: process.env.GITHUB_TOKEN,
});
if (result.exitCode === 0) {
	console.log(result.message);
} else {
	console.error(result.message);
}
process.exitCode = result.exitCode;
