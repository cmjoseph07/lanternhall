import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runReleaseAgeCheck } from "./release-age";

// Synthetic registry metadata served by a local fake; no real registry is called.
const now = new Date("2026-11-06T12:00:00Z");
const old = "2026-10-20T08:00:00Z";
const young = "2026-11-03T09:30:00Z";
const exactlySevenDays = "2026-10-30T12:00:00Z";

const digestA = `sha256:${"a".repeat(64)}`;
const digestB = `sha256:${"b".repeat(64)}`;

type FakeData = {
	npm: Record<string, Record<string, string>>;
	// null serves a release without a publish date, as GitHub does for drafts.
	github: Record<string, Record<string, string | null>>;
	dockerHub: Record<string, { digest: string; pushed: string }>;
	failWith?: number;
};

let fake: FakeData;
let requests: { path: string; authorization: string | null }[];
let server: ReturnType<typeof Bun.serve>;
let root: string;

function json(body: unknown, status = 200): Response {
	return Response.json(body, { status });
}

function serveNpm(name: string): Response {
	const times = fake.npm[name];
	if (times === undefined) {
		return json({ error: "Not found" }, 404);
	}
	const versions = Object.fromEntries(Object.keys(times).map((version) => [version, {}]));
	return json({ name, versions, time: { created: old, ...times } });
}

function serveGithub(repo: string, tag: string): Response {
	const releases = fake.github[repo];
	if (releases === undefined || !(tag in releases)) {
		return json({ message: "Not Found" }, 404);
	}
	return json({ tag_name: tag, published_at: releases[tag] });
}

function serveDockerHub(namespace: string, repo: string, tag: string): Response {
	const entry = fake.dockerHub[`${namespace}/${repo}:${tag}`];
	if (entry === undefined) {
		return json({ message: "object not found" }, 404);
	}
	return json({ name: tag, digest: entry.digest, tag_last_pushed: entry.pushed });
}

function route(url: URL): Response {
	const path = decodeURIComponent(url.pathname);
	const npm = path.match(/^\/npm\/(.+)$/);
	if (npm?.[1] !== undefined) {
		return serveNpm(npm[1]);
	}
	const github = path.match(/^\/github\/repos\/([^/]+\/[^/]+)\/releases\/tags\/(.+)$/);
	if (github?.[1] !== undefined && github[2] !== undefined) {
		return serveGithub(github[1], github[2]);
	}
	const hub = path.match(/^\/hub\/v2\/namespaces\/([^/]+)\/repositories\/([^/]+)\/tags\/(.+)$/);
	if (hub?.[1] !== undefined && hub[2] !== undefined && hub[3] !== undefined) {
		return serveDockerHub(hub[1], hub[2], hub[3]);
	}
	return json({ message: "unexpected path" }, 400);
}

beforeAll(() => {
	server = Bun.serve({
		hostname: "127.0.0.1",
		port: 0,
		fetch(request) {
			const url = new URL(request.url);
			requests.push({ path: url.pathname, authorization: request.headers.get("authorization") });
			return fake.failWith === undefined
				? route(url)
				: json({ message: "upstream down" }, fake.failWith);
		},
	});
});

afterAll(async () => {
	await server.stop(true);
});

beforeEach(async () => {
	root = await mkdtemp(join(tmpdir(), "lanternhall-release-age-"));
	requests = [];
	fake = {
		npm: {
			typescript: { "6.0.3": old },
			"@biomejs/biome": { "2.6.4": old },
			zod: { "4.6.7": old },
		},
		github: {
			"oven-sh/bun": { "bun-v1.4.4": old },
			"trailbaseio/trailbase": { "v0.35.8": old },
			"evilmartians/lefthook": { "v2.2.2": old },
		},
		dockerHub: {
			"library/caddy:2.11.7-alpine": { digest: digestA, pushed: old },
			"valkey/valkey:9.1.3-alpine": { digest: digestB, pushed: old },
		},
	};
});

afterEach(async () => {
	await rm(root, { recursive: true, force: true });
});

const goodPackageJson = {
	name: "fixture",
	private: true,
	devDependencies: { typescript: "6.0.3", "@biomejs/biome": "2.6.4" },
	dependencies: { zod: "4.6.7" },
};

const goodMiseToml = [
	"[tools]",
	'bun = "1.4.4"',
	'"github:trailbaseio/trailbase" = "0.35.8"',
	'"github:evilmartians/lefthook" = { version = "2.2.2", bin = "lefthook" }',
	"",
	"[settings]",
	'experimental = "1.0"',
	"",
].join("\n");

const goodCompose = [
	"services:",
	"  caddy:",
	`    image: caddy:2.11.7-alpine@${digestA}`,
	"  valkey:",
	`    image: docker.io/valkey/valkey:9.1.3-alpine@${digestB}`,
	"  service:",
	"    build: .",
	"",
].join("\n");

async function writeRepo(files: {
	packageJson?: unknown;
	miseToml?: string;
	compose?: string | null;
}): Promise<void> {
	await writeFile(
		join(root, "package.json"),
		JSON.stringify(files.packageJson ?? goodPackageJson, null, "\t"),
	);
	await writeFile(join(root, "mise.toml"), files.miseToml ?? goodMiseToml);
	if (files.compose !== null) {
		await mkdir(join(root, "deploy"), { recursive: true });
		await writeFile(join(root, "deploy", "compose.yaml"), files.compose ?? goodCompose);
	}
}

function check(githubToken?: string, origin = server.url.origin) {
	return runReleaseAgeCheck({
		cwd: root,
		now,
		githubToken,
		registries: {
			npm: `${origin}/npm`,
			github: `${origin}/github`,
			dockerHub: `${origin}/hub`,
		},
	});
}

describe("runReleaseAgeCheck", () => {
	test("exact pins published 7+ days ago in all three files pass", async () => {
		await writeRepo({});

		const result = await check();

		expect(result).toEqual({
			exitCode: 0,
			message: "Release-age check passed (8 pins, each published 7+ days before now).",
		});
	});

	test("an npm pin published less than 7 days ago fails, naming dependency, version and date", async () => {
		fake.npm.typescript = { "6.0.3": young };
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toBe(
			[
				"Release-age check failed: 1 of 8 pins break the 7-day rule.",
				"  package.json devDependencies typescript 6.0.3: published 2026-11-03T09:30:00.000Z, less than 7 days ago (allowed from 2026-11-10T09:30:00.000Z).",
			].join("\n"),
		);
	});

	test("a mise tool released less than 7 days ago fails", async () => {
		fake.github["trailbaseio/trailbase"] = { "v0.35.8": young };
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			"mise.toml tools github:trailbaseio/trailbase 0.35.8: published 2026-11-03T09:30:00.000Z, less than 7 days ago",
		);
	});

	test("a Compose image pushed less than 7 days ago fails", async () => {
		fake.dockerHub["valkey/valkey:9.1.3-alpine"] = { digest: digestB, pushed: young };
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			`deploy/compose.yaml services.valkey docker.io/valkey/valkey 9.1.3-alpine@${digestB}: published 2026-11-03T09:30:00.000Z, less than 7 days ago`,
		);
	});

	test("a pin published exactly 7 days ago passes", async () => {
		fake.npm.zod = { "4.6.7": exactlySevenDays };
		await writeRepo({});

		expect((await check()).exitCode).toBe(0);
	});

	test("range specifiers and non-exact versions fail without a registry lookup", async () => {
		await writeRepo({
			packageJson: {
				devDependencies: { typescript: "^6.0.3", "@biomejs/biome": "~2.6.4" },
				dependencies: { zod: "latest" },
				optionalDependencies: { left: "github:owner/left" },
			},
			miseToml: '[tools]\nbun = "latest"\n"github:trailbaseio/trailbase" = "0.35"\n',
			compose: [
				"services:",
				"  caddy:",
				"    image: caddy:latest",
				"  valkey:",
				"    image: valkey/valkey:9.1.3-alpine",
				"",
			].join("\n"),
		});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toBe(
			[
				"Release-age check failed: 8 of 8 pins break the 7-day rule.",
				'  package.json dependencies zod "latest": not an exact version; pin one exact version.',
				'  package.json devDependencies typescript "^6.0.3": not an exact version; pin one exact version.',
				'  package.json devDependencies @biomejs/biome "~2.6.4": not an exact version; pin one exact version.',
				'  package.json optionalDependencies left "github:owner/left": not an exact version; pin one exact version.',
				'  mise.toml tools bun "latest": not an exact version; pin one exact version.',
				'  mise.toml tools github:trailbaseio/trailbase "0.35": not an exact version; pin one exact version.',
				'  deploy/compose.yaml services.caddy "caddy:latest": not an exact image; pin an exact version tag and its digest (name:tag@sha256:...).',
				'  deploy/compose.yaml services.valkey "valkey/valkey:9.1.3-alpine": not an exact image; pin an exact version tag and its digest (name:tag@sha256:...).',
			].join("\n"),
		);
		expect(requests).toEqual([]);
	});

	test("a missing deploy/compose.yaml is not an error", async () => {
		await writeRepo({ compose: null });

		const result = await check();

		expect(result).toEqual({
			exitCode: 0,
			message: "Release-age check passed (6 pins, each published 7+ days before now).",
		});
	});

	test("GitHub tags are tried with and without a v prefix", async () => {
		fake.github["evilmartians/lefthook"] = { "2.2.2": old };
		await writeRepo({ compose: null });

		expect((await check()).exitCode).toBe(0);
		expect(requests.map((request) => request.path)).toContain(
			"/github/repos/evilmartians/lefthook/releases/tags/2.2.2",
		);
	});

	test("GitHub requests carry the token when one is given", async () => {
		await writeRepo({ compose: null });

		await check("test-token");

		const github = requests.filter((request) => request.path.startsWith("/github/"));
		expect(github.length).toBeGreaterThan(0);
		expect(github.every((request) => request.authorization === "Bearer test-token")).toBe(true);
		const others = requests.filter((request) => !request.path.startsWith("/github/"));
		expect(others.every((request) => request.authorization === null)).toBe(true);
	});

	test("a pinned version the registry does not know fails", async () => {
		fake.npm.zod = { "4.6.6": old };
		delete fake.github["oven-sh/bun"];
		await writeRepo({ compose: null });

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			"package.json dependencies zod 4.6.7: version not found on the npm registry.",
		);
		expect(result.message).toContain(
			"mise.toml tools bun 1.4.4: no GitHub release oven-sh/bun bun-v1.4.4.",
		);
	});

	test("an npm package the registry does not know fails", async () => {
		delete fake.npm.zod;
		await writeRepo({ compose: null });

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			"package.json dependencies zod 4.6.7: version not found on the npm registry.",
		);
	});

	test("an image digest that is not the tag's current digest fails", async () => {
		fake.dockerHub["library/caddy:2.11.7-alpine"] = { digest: digestB, pushed: old };
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			`deploy/compose.yaml services.caddy docker.io/library/caddy 2.11.7-alpine@${digestA}: Docker Hub tag now points to ${digestB}, so the pinned digest cannot be dated; re-pin to the current digest.`,
		);
	});

	test("an image tag Docker Hub does not know fails", async () => {
		delete fake.dockerHub["valkey/valkey:9.1.3-alpine"];
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			`deploy/compose.yaml services.valkey docker.io/valkey/valkey 9.1.3-alpine@${digestB}: tag not found on Docker Hub.`,
		);
	});

	test("images outside Docker Hub and mise tools without a known release source fail", async () => {
		await writeRepo({
			miseToml: '[tools]\nbun = "1.4.4"\nnode = "24.11.0"\n"aqua:owner/tool" = "1.0.0"\n',
			compose: `services:\n  app:\n    image: ghcr.io/owner/app:1.0.0@${digestA}\n`,
		});

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toContain(
			"mise.toml tools node 24.11.0: no release source known; use the github: backend.",
		);
		expect(result.message).toContain(
			"mise.toml tools aqua:owner/tool 1.0.0: no release source known; use the github: backend.",
		);
		expect(result.message).toContain(
			`deploy/compose.yaml services.app ghcr.io/owner/app 1.0.0@${digestA}: only Docker Hub images can be dated.`,
		);
	});

	test("a registry that cannot be reached exits 2 and names the failing lookup", async () => {
		fake.failWith = 503;
		await writeRepo({ compose: null });

		const result = await check();

		expect(result.exitCode).toBe(2);
		expect(result.message).toStartWith(
			"Release-age check could not finish: 6 of 6 lookups failed.",
		);
		expect(result.message).toContain(
			"  package.json dependencies zod 4.6.7: npm registry answered 503 for",
		);
	});

	test("a registry refusing the connection exits 2", async () => {
		await writeRepo({
			packageJson: { dependencies: { zod: "4.6.7" } },
			miseToml: "",
			compose: null,
		});
		const closed = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
		const origin = closed.url.origin;
		await closed.stop(true);

		const result = await check(undefined, origin);

		expect(result.exitCode).toBe(2);
		expect(result.message).toContain(
			`  package.json dependencies zod 4.6.7: npm registry request failed for ${origin}/npm/zod:`,
		);
	});

	test("unexpected registry metadata or an unreadable date exits 2", async () => {
		fake.github["trailbaseio/trailbase"] = { "v0.35.8": null };
		fake.dockerHub["library/caddy:2.11.7-alpine"] = { digest: digestA, pushed: "last Tuesday" };
		await writeRepo({});

		const result = await check();

		expect(result.exitCode).toBe(2);
		expect(result.message).toBe(
			[
				"Release-age check could not finish: 2 of 8 lookups failed.",
				`  mise.toml tools github:trailbaseio/trailbase 0.35.8: GitHub sent unexpected metadata for ${server.url.origin}/github/repos/trailbaseio/trailbase/releases/tags/v0.35.8.`,
				`  deploy/compose.yaml services.caddy docker.io/library/caddy 2.11.7-alpine@${digestA}: unreadable publish date "last Tuesday".`,
			].join("\n"),
		);
	});

	test("a policy failure wins over a lookup error in the exit code", async () => {
		await writeRepo({
			packageJson: { dependencies: { zod: "^4.6.7" } },
			miseToml: '[tools]\nbun = "1.4.4"\n',
			compose: null,
		});
		fake.failWith = 500;

		const result = await check();

		expect(result.exitCode).toBe(1);
		expect(result.message).toBe(
			[
				"Release-age check failed: 1 of 2 pins break the 7-day rule; 1 lookup could not finish.",
				'  package.json dependencies zod "^4.6.7": not an exact version; pin one exact version.',
				`  mise.toml tools bun 1.4.4: GitHub answered 500 for ${server.url.origin}/github/repos/oven-sh/bun/releases/tags/bun-v1.4.4.`,
			].join("\n"),
		);
	});

	test("unreadable or malformed pin files exit 2", async () => {
		await writeRepo({ miseToml: "[tools\n" });
		const badToml = await check();
		expect(badToml.exitCode).toBe(2);
		expect(badToml.message).toStartWith("Release-age check could not read mise.toml:");

		await writeRepo({ compose: "services: [unclosed\n" });
		const badYaml = await check();
		expect(badYaml.exitCode).toBe(2);
		expect(badYaml.message).toStartWith("Release-age check could not read deploy/compose.yaml:");

		await rm(join(root, "package.json"));
		const missing = await check();
		expect(missing.exitCode).toBe(2);
		expect(missing.message).toStartWith("Release-age check could not read package.json:");
	});
});
