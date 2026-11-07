import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";

export type ReleaseAgeCheckResult = { exitCode: 0 | 1 | 2; message: string };

/** Base URLs, injectable so tests can point every lookup at a local fake. */
export type Registries = { npm: string; github: string; dockerHub: string };

export const defaultRegistries: Registries = {
	npm: "https://registry.npmjs.org",
	github: "https://api.github.com",
	dockerHub: "https://hub.docker.com",
};

const minimumAgeMs = 7 * 24 * 60 * 60 * 1000;
const requestTimeoutMs = 30_000;
const userAgent = "lanternhall-release-age-check";

// One exact SemVer version, optionally with prerelease and build parts.
const exactVersion = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
// An image tag that names one exact version, such as `9.1.3-alpine`.
const exactImageTag = /^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
const imageReference =
	/^(?<name>[a-z0-9][a-z0-9._/-]*):(?<tag>[\w][\w.-]{0,127})@(?<digest>sha256:[a-f0-9]{64})$/;
const githubRepository = /^[\w.-]+\/[\w.-]+$/;

/** mise short names whose releases live on GitHub under a non-standard tag. */
const miseShortNames: Record<string, { repository: string; tagPrefix: string }> = {
	bun: { repository: "oven-sh/bun", tagPrefix: "bun-v" },
};

type Outcome = { kind: "ok" } | { kind: "violation" | "error"; detail: string };

/** One pinned version and the check that dates it. */
type Pin = { subject: string; check: () => Promise<Outcome> };

type Context = { now: Date; registries: Registries; githubToken: string | undefined };

function violation(detail: string): Outcome {
	return { kind: "violation", detail };
}

function invalidPin(subject: string, detail: string): Pin {
	return { subject, check: async () => violation(detail) };
}

function messageOf(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function judgeAge(published: string, now: Date): Outcome {
	const date = new Date(published);
	if (Number.isNaN(date.getTime())) {
		return { kind: "error", detail: `unreadable publish date "${published}".` };
	}
	if (now.getTime() - date.getTime() >= minimumAgeMs) {
		return { kind: "ok" };
	}
	const allowedFrom = new Date(date.getTime() + minimumAgeMs).toISOString();
	return violation(
		`published ${date.toISOString()}, less than 7 days ago (allowed from ${allowedFrom}).`,
	);
}

/** Returns the parsed body, or null on 404; anything else non-2xx throws. */
async function getJson<T>(
	url: string,
	service: string,
	schema: z.ZodType<T>,
	headers: Record<string, string> = {},
): Promise<T | null> {
	let response: Response;
	try {
		response = await fetch(url, {
			headers: { "user-agent": userAgent, ...headers },
			signal: AbortSignal.timeout(requestTimeoutMs),
		});
	} catch (error) {
		throw new Error(`${service} request failed for ${url}: ${messageOf(error)}`);
	}
	if (response.status === 404) {
		return null;
	}
	if (!response.ok) {
		throw new Error(`${service} answered ${response.status} for ${url}.`);
	}
	const parsed = schema.safeParse(await response.json());
	if (!parsed.success) {
		throw new Error(`${service} sent unexpected metadata for ${url}.`);
	}
	return parsed.data;
}

async function settle(lookup: () => Promise<Outcome>): Promise<Outcome> {
	try {
		return await lookup();
	} catch (error) {
		return { kind: "error", detail: messageOf(error) };
	}
}

const npmPackument = z.object({
	versions: z.record(z.string(), z.unknown()),
	time: z.record(z.string(), z.unknown()),
});

function npmPin(subject: string, name: string, version: string, context: Context): Pin {
	const path = name.startsWith("@")
		? `@${encodeURIComponent(name.slice(1))}`
		: encodeURIComponent(name);
	const url = `${context.registries.npm}/${path}`;
	return {
		subject,
		check: () =>
			settle(async () => {
				// The abbreviated document lacks `time`, so the full one is needed.
				const packument = await getJson(url, "npm registry", npmPackument);
				const published = packument?.time[version];
				if (packument?.versions[version] === undefined || typeof published !== "string") {
					return violation("version not found on the npm registry.");
				}
				return judgeAge(published, context.now);
			}),
	};
}

const githubRelease = z.object({ published_at: z.string() });

function githubPin(subject: string, repository: string, tags: string[], context: Context): Pin {
	const headers: Record<string, string> = {
		accept: "application/vnd.github+json",
		"x-github-api-version": "2022-11-28",
	};
	if (context.githubToken !== undefined && context.githubToken !== "") {
		headers.authorization = `Bearer ${context.githubToken}`;
	}
	return {
		subject,
		check: () =>
			settle(async () => {
				for (const tag of tags) {
					const url = `${context.registries.github}/repos/${repository}/releases/tags/${encodeURIComponent(tag)}`;
					const release = await getJson(url, "GitHub", githubRelease, headers);
					if (release !== null) {
						return judgeAge(release.published_at, context.now);
					}
				}
				return violation(`no GitHub release ${repository} ${tags.join(" or ")}.`);
			}),
	};
}

const dockerHubTag = z.object({ digest: z.string(), tag_last_pushed: z.string() });

function dockerHubPin(
	subject: string,
	image: { namespace: string; repository: string; tag: string; digest: string },
	context: Context,
): Pin {
	const url = `${context.registries.dockerHub}/v2/namespaces/${image.namespace}/repositories/${image.repository}/tags/${encodeURIComponent(image.tag)}`;
	return {
		subject,
		check: () =>
			settle(async () => {
				const tag = await getJson(url, "Docker Hub", dockerHubTag);
				if (tag === null) {
					return violation("tag not found on Docker Hub.");
				}
				// Docker Hub dates only the tag's current digest; an older digest has no date.
				if (tag.digest !== image.digest) {
					return violation(
						`Docker Hub tag now points to ${tag.digest}, so the pinned digest cannot be dated; re-pin to the current digest.`,
					);
				}
				return judgeAge(tag.tag_last_pushed, context.now);
			}),
	};
}

const notExactVersion = "not an exact version; pin one exact version.";

const packageJsonSchema = z.object({
	dependencies: z.record(z.string(), z.string()).optional(),
	devDependencies: z.record(z.string(), z.string()).optional(),
	optionalDependencies: z.record(z.string(), z.string()).optional(),
});

function packageJsonPins(text: string, context: Context): Pin[] {
	const manifest = packageJsonSchema.parse(JSON.parse(text));
	const sections = ["dependencies", "devDependencies", "optionalDependencies"] as const;
	return sections.flatMap((section) =>
		Object.entries(manifest[section] ?? {}).map(([name, specifier]) => {
			const where = `package.json ${section} ${name}`;
			return exactVersion.test(specifier)
				? npmPin(`${where} ${specifier}`, name, specifier, context)
				: invalidPin(`${where} ${JSON.stringify(specifier)}`, notExactVersion);
		}),
	);
}

const miseTomlSchema = z.object({ tools: z.record(z.string(), z.unknown()).optional() });

function miseVersion(value: unknown): string | null {
	if (typeof value === "string") {
		return value;
	}
	const table = z.object({ version: z.string() }).safeParse(value);
	return table.success ? table.data.version : null;
}

function miseToolPin(tool: string, value: unknown, context: Context): Pin {
	const where = `mise.toml tools ${tool}`;
	const version = miseVersion(value);
	if (version === null || !exactVersion.test(version)) {
		return invalidPin(`${where} ${JSON.stringify(version ?? value)}`, notExactVersion);
	}
	const subject = `${where} ${version}`;
	const shortName = miseShortNames[tool];
	if (shortName !== undefined) {
		return githubPin(subject, shortName.repository, [`${shortName.tagPrefix}${version}`], context);
	}
	const repository = tool.startsWith("github:") ? tool.slice("github:".length) : "";
	if (!githubRepository.test(repository)) {
		return invalidPin(subject, "no release source known; use the github: backend.");
	}
	// mise accepts the version with or without the tag's `v`.
	return githubPin(subject, repository, [`v${version}`, version], context);
}

function miseTomlPins(text: string, context: Context): Pin[] {
	const config = miseTomlSchema.parse(Bun.TOML.parse(text));
	return Object.entries(config.tools ?? {}).map(([tool, value]) =>
		miseToolPin(tool, value, context),
	);
}

const composeSchema = z.object({
	services: z.record(z.string(), z.object({ image: z.string().optional() })).optional(),
});

const notExactImage =
	"not an exact image; pin an exact version tag and its digest (name:tag@sha256:...).";

function imagePin(service: string, reference: string, context: Context): Pin {
	const where = `deploy/compose.yaml services.${service}`;
	const groups = reference.match(imageReference)?.groups;
	const name = groups?.name;
	const tag = groups?.tag;
	const digest = groups?.digest;
	if (name === undefined || tag === undefined || digest === undefined || !exactImageTag.test(tag)) {
		return invalidPin(`${where} ${JSON.stringify(reference)}`, notExactImage);
	}
	const parts = name.split("/");
	const first = parts[0] ?? "";
	const hasRegistry =
		parts.length > 1 && (first.includes(".") || first.includes(":") || first === "localhost");
	const registry = hasRegistry ? first : "docker.io";
	const path = hasRegistry ? parts.slice(1) : parts;
	const isDockerHub = registry === "docker.io" || registry === "index.docker.io";
	const [namespace, repository] = path.length === 1 ? ["library", path[0]] : path;
	if (!isDockerHub || path.length > 2 || namespace === undefined || repository === undefined) {
		return invalidPin(
			`${where} ${registry}/${path.join("/")} ${tag}@${digest}`,
			"only Docker Hub images can be dated.",
		);
	}
	const subject = `${where} docker.io/${namespace}/${repository} ${tag}@${digest}`;
	return dockerHubPin(subject, { namespace, repository, tag, digest }, context);
}

function composePins(text: string, context: Context): Pin[] {
	const compose = composeSchema.parse(Bun.YAML.parse(text));
	return Object.entries(compose.services ?? {}).flatMap(([service, definition]) =>
		definition.image === undefined ? [] : [imagePin(service, definition.image, context)],
	);
}

function isMissingFile(error: unknown): boolean {
	return error instanceof Error && "code" in error && error.code === "ENOENT";
}

type PinFile = {
	path: string;
	parse: (text: string, context: Context) => Pin[];
	optional: boolean;
};

const pinFiles: PinFile[] = [
	{ path: "package.json", parse: packageJsonPins, optional: false },
	{ path: "mise.toml", parse: miseTomlPins, optional: false },
	{ path: "deploy/compose.yaml", parse: composePins, optional: true },
];

type PinRead = { ok: true; pins: Pin[] } | { ok: false; message: string };

async function readPins(cwd: string, file: PinFile, context: Context): Promise<PinRead> {
	try {
		const text = await readFile(join(cwd, file.path), "utf8");
		return { ok: true, pins: file.parse(text, context) };
	} catch (error) {
		if (file.optional && isMissingFile(error)) {
			return { ok: true, pins: [] };
		}
		return {
			ok: false,
			message: `Release-age check could not read ${file.path}: ${messageOf(error)}`,
		};
	}
}

function plural(count: number, word: string): string {
	return `${count} ${word}${count === 1 ? "" : "s"}`;
}

function report(results: { subject: string; outcome: Outcome }[]): ReleaseAgeCheckResult {
	const total = results.length;
	const lines: string[] = [];
	let violations = 0;
	let errors = 0;
	for (const { subject, outcome } of results) {
		if (outcome.kind === "ok") {
			continue;
		}
		if (outcome.kind === "violation") {
			violations += 1;
		} else {
			errors += 1;
		}
		lines.push(`  ${subject}: ${outcome.detail}`);
	}
	if (violations > 0) {
		const unfinished = errors > 0 ? `; ${plural(errors, "lookup")} could not finish` : "";
		const header = `Release-age check failed: ${violations} of ${plural(total, "pin")} break the 7-day rule${unfinished}.`;
		return { exitCode: 1, message: [header, ...lines].join("\n") };
	}
	if (errors > 0) {
		const header = `Release-age check could not finish: ${errors} of ${plural(total, "lookup")} failed.`;
		return { exitCode: 2, message: [header, ...lines].join("\n") };
	}
	return {
		exitCode: 0,
		message: `Release-age check passed (${plural(total, "pin")}, each published 7+ days before now).`,
	};
}

/**
 * Checks that every version pinned in `package.json`, `mise.toml` and
 * `deploy/compose.yaml` (when present) is exact and was published at least
 * 7 days before `now`, using npm `time`, GitHub release `published_at` and
 * Docker Hub `tag_last_pushed`.
 * Exit 1 when a pin breaks the rule, 2 when the check could not finish.
 */
export async function runReleaseAgeCheck(options: {
	cwd: string;
	now: Date;
	registries: Registries;
	githubToken?: string | undefined;
}): Promise<ReleaseAgeCheckResult> {
	const context: Context = {
		now: options.now,
		registries: options.registries,
		githubToken: options.githubToken,
	};
	const pins: Pin[] = [];
	for (const file of pinFiles) {
		const read = await readPins(options.cwd, file, context);
		if (!read.ok) {
			return { exitCode: 2, message: read.message };
		}
		pins.push(...read.pins);
	}
	const results = await Promise.all(
		pins.map(async (pin) => ({ subject: pin.subject, outcome: await pin.check() })),
	);
	return report(results);
}
