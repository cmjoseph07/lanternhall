import { join } from "node:path";

const repoRoot = join(import.meta.dir, "..", "..", "..", "..");

export const trailbaseConfigTemplatePath = join(
	repoRoot,
	"deploy",
	"trailbase",
	"config.textproto",
);

export function readTrailbaseConfigTemplate(): Promise<string> {
	return Bun.file(trailbaseConfigTemplatePath).text();
}

export type TextprotoScalar = { kind: "string" | "number" | "identifier"; text: string };

/** A parsed message: every field maps to all its values, so repeated fields and lists merge. */
export type TextprotoMessage = Map<string, TextprotoValue[]>;

export type TextprotoValue = TextprotoScalar | TextprotoMessage;

export class TextprotoSyntaxError extends Error {
	constructor(line: number, reason: string) {
		super(`line ${line}: ${reason}`);
		this.name = "TextprotoSyntaxError";
	}
}

type Token = {
	kind: "string" | "number" | "identifier" | "punctuation";
	text: string;
	line: number;
};

const punctuation = new Set(["{", "}", "[", "]", ":", ",", ";"]);
const escapes: Record<string, string> = { n: "\n", r: "\r", t: "\t" };
const identifierPattern = /[A-Za-z_][A-Za-z0-9_]*/y;
const numberPattern = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/y;

function readString(text: string, start: number, line: number): { value: string; end: number } {
	const quote = text[start];
	let value = "";
	let index = start + 1;
	while (index < text.length && text[index] !== quote && text[index] !== "\n") {
		const char = text[index] as string;
		if (char === "\\" && index + 1 < text.length) {
			const next = text[index + 1] as string;
			value += escapes[next] ?? next;
			index += 2;
		} else {
			value += char;
			index += 1;
		}
	}
	if (text[index] !== quote) {
		throw new TextprotoSyntaxError(line, "unterminated string");
	}
	return { value, end: index + 1 };
}

function matchAt(pattern: RegExp, text: string, index: number): string | undefined {
	pattern.lastIndex = index;
	return pattern.exec(text)?.[0];
}

function tokenize(text: string): { tokens: Token[]; lastLine: number } {
	const tokens: Token[] = [];
	let line = 1;
	let index = 0;
	while (index < text.length) {
		const char = text[index] as string;
		if (char === "\n") {
			line += 1;
			index += 1;
		} else if (/\s/.test(char)) {
			index += 1;
		} else if (char === "#") {
			const end = text.indexOf("\n", index);
			index = end === -1 ? text.length : end;
		} else if (punctuation.has(char)) {
			tokens.push({ kind: "punctuation", text: char, line });
			index += 1;
		} else if (char === '"' || char === "'") {
			const { value, end } = readString(text, index, line);
			tokens.push({ kind: "string", text: value, line });
			index = end;
		} else {
			const identifier = matchAt(identifierPattern, text, index);
			const number = identifier === undefined ? matchAt(numberPattern, text, index) : undefined;
			const word = identifier ?? number;
			if (word === undefined) {
				throw new TextprotoSyntaxError(line, `unexpected character '${char}'`);
			}
			tokens.push({ kind: identifier === undefined ? "number" : "identifier", text: word, line });
			index += word.length;
		}
	}
	return { tokens, lastLine: line };
}

/**
 * Parses the protobuf text format subset TrailBase writes: fields, nested `{}` messages,
 * `[]` lists, strings, numbers, identifiers and `#` comments. Values are not checked
 * against the schema; TrailBase does that when it loads the file.
 */
export function parseTextproto(text: string): TextprotoMessage {
	const { tokens, lastLine } = tokenize(text);
	let position = 0;

	const fail = (reason: string, found: Token | undefined): never => {
		const what = found === undefined ? "end of input" : `'${found.text}'`;
		throw new TextprotoSyntaxError(found?.line ?? lastLine, `${reason}, found ${what}`);
	};
	const isPunctuation = (token: Token | undefined, text: string) =>
		token?.kind === "punctuation" && token.text === text;

	function parseMessage(nested: boolean): TextprotoMessage {
		const message: TextprotoMessage = new Map();
		for (;;) {
			const token = tokens[position];
			if (token === undefined && !nested) {
				return message;
			}
			if (isPunctuation(token, "}") && nested) {
				position += 1;
				return message;
			}
			if (token?.kind !== "identifier") {
				return fail(nested ? "expected a field name or }" : "expected a field name", token);
			}
			position += 1;
			const values = message.get(token.text) ?? [];
			message.set(token.text, values);
			const next = tokens[position];
			if (isPunctuation(next, ":")) {
				position += 1;
				values.push(...parseFieldValue());
			} else if (isPunctuation(next, "{")) {
				position += 1;
				values.push(parseMessage(true));
			} else {
				fail(`expected : or { after ${token.text}`, next);
			}
			if (isPunctuation(tokens[position], ",") || isPunctuation(tokens[position], ";")) {
				position += 1;
			}
		}
	}

	function parseFieldValue(): TextprotoValue[] {
		if (!isPunctuation(tokens[position], "[")) {
			return [parseValue()];
		}
		position += 1;
		const values: TextprotoValue[] = [];
		if (isPunctuation(tokens[position], "]")) {
			position += 1;
			return values;
		}
		for (;;) {
			values.push(parseValue());
			const token = tokens[position];
			position += 1;
			if (isPunctuation(token, "]")) {
				return values;
			}
			if (!isPunctuation(token, ",")) {
				return fail("expected , or ]", token);
			}
		}
	}

	function parseValue(): TextprotoValue {
		const token = tokens[position];
		if (isPunctuation(token, "{")) {
			position += 1;
			return parseMessage(true);
		}
		if (token === undefined || token.kind === "punctuation") {
			return fail("expected a value", token);
		}
		position += 1;
		return { kind: token.kind, text: token.text };
	}

	return parseMessage(false);
}

function messages(message: TextprotoMessage, field: string): TextprotoMessage[] {
	return (message.get(field) ?? []).filter((value) => value instanceof Map);
}

function scalar(message: TextprotoMessage, field: string): TextprotoScalar | undefined {
	const value = message.get(field)?.at(-1);
	return value instanceof Map ? undefined : value;
}

function isIdentifier(message: TextprotoMessage, field: string, expected: string): boolean {
	const value = scalar(message, field);
	return value?.kind === "identifier" && value.text === expected;
}

/** Dotted paths of every field with this name, at any depth. */
function findFields(message: TextprotoMessage, field: string, prefix = ""): string[] {
	const found: string[] = [];
	for (const [name, values] of message) {
		const path = `${prefix}${name}`;
		if (name === field) {
			found.push(path);
		}
		for (const value of values) {
			if (value instanceof Map) {
				found.push(...findFields(value, field, `${path}.`));
			}
		}
	}
	return found;
}

const backupJob = 'jobs.system_jobs needs { id: BACKUP, schedule: "@daily", disabled: false }';

/**
 * Checks a TrailBase config against the platform rules and returns one line per problem
 * (empty when the config passes).
 */
export function lintTrailbaseConfig(text: string): string[] {
	let config: TextprotoMessage;
	try {
		config = parseTextproto(text);
	} catch (error) {
		if (error instanceof TextprotoSyntaxError) {
			return [`config.textproto: ${error.message}`];
		}
		throw error;
	}

	const problems: string[] = [];
	const servers = messages(config, "server");
	if (!servers.some((server) => isIdentifier(server, "enable_record_transactions", "true"))) {
		problems.push("server.enable_record_transactions must be true");
	}
	const jobs = messages(config, "jobs").flatMap((entry) => messages(entry, "system_jobs"));
	const hasBackup = jobs.some(
		(job) =>
			isIdentifier(job, "id", "BACKUP") &&
			scalar(job, "schedule")?.text === "@daily" &&
			isIdentifier(job, "disabled", "false"),
	);
	if (!hasBackup) {
		problems.push(backupJob);
	}

	for (const api of messages(config, "record_apis")) {
		const name = scalar(api, "name")?.text ?? "(unnamed)";
		if (api.has("acl_world")) {
			problems.push(`record API "${name}": acl_world is not allowed; use acl_authenticated only`);
		}
		if ((api.get("acl_authenticated") ?? []).length === 0) {
			problems.push(`record API "${name}": acl_authenticated must grant at least one permission`);
		}
		if (!isIdentifier(api, "enable_subscriptions", "true")) {
			problems.push(`record API "${name}": enable_subscriptions must be true`);
		}
	}

	for (const path of findFields(config, "acl_world")) {
		if (path !== "record_apis.acl_world") {
			problems.push(`${path}: acl_world is not allowed anywhere`);
		}
	}
	return problems;
}
