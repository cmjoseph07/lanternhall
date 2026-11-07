import { describe, expect, test } from "bun:test";
import {
	lintTrailbaseConfig,
	parseTextproto,
	readTrailbaseConfigTemplate,
	type TextprotoValue,
} from "./trailbase-config";

const base = `
server { enable_record_transactions: true }
jobs { system_jobs: [{ id: BACKUP, schedule: "@daily", disabled: false }] }
`;

function recordApi(fields: string): string {
	return `record_apis: [{ name: "notes" table_name: "notes" ${fields} }]`;
}

const goodApi = recordApi("acl_authenticated: [CREATE, READ] enable_subscriptions: true");

describe("lintTrailbaseConfig", () => {
	test("passes the committed template", async () => {
		expect(lintTrailbaseConfig(await readTrailbaseConfigTemplate())).toEqual([]);
	});

	test("passes a record API with authenticated access and subscriptions", () => {
		expect(lintTrailbaseConfig(`${base}${goodApi}`)).toEqual([]);
	});

	test("fails on acl_world in a record API", () => {
		const config = `${base}${recordApi(
			"acl_world: [READ] acl_authenticated: [READ] enable_subscriptions: true",
		)}`;
		expect(lintTrailbaseConfig(config)).toEqual([
			'record API "notes": acl_world is not allowed; use acl_authenticated only',
		]);
	});

	test("fails on acl_world anywhere in the config", () => {
		expect(lintTrailbaseConfig(`${base}${goodApi}\nauth { acl_world: [READ] }`)).toEqual([
			"auth.acl_world: acl_world is not allowed anywhere",
		]);
	});

	test("fails on a record API without acl_authenticated", () => {
		expect(lintTrailbaseConfig(`${base}${recordApi("enable_subscriptions: true")}`)).toEqual([
			'record API "notes": acl_authenticated must grant at least one permission',
		]);
	});

	test("fails on a record API without subscriptions", () => {
		const missing = `${base}${recordApi("acl_authenticated: [READ]")}`;
		const disabled = `${base}${recordApi("acl_authenticated: [READ] enable_subscriptions: false")}`;
		const message = 'record API "notes": enable_subscriptions must be true';
		expect(lintTrailbaseConfig(missing)).toEqual([message]);
		expect(lintTrailbaseConfig(disabled)).toEqual([message]);
	});

	test("checks every record API, including repeated record_apis fields", () => {
		const config = `${base}${goodApi}
record_apis { name: "tags" table_name: "tags" acl_authenticated: [READ] }`;
		expect(lintTrailbaseConfig(config)).toEqual([
			'record API "tags": enable_subscriptions must be true',
		]);
	});

	test("fails without record transactions", () => {
		const config = `jobs { system_jobs: [{ id: BACKUP, schedule: "@daily", disabled: false }] }`;
		expect(lintTrailbaseConfig(config)).toEqual(["server.enable_record_transactions must be true"]);
	});

	test("fails without an enabled daily BACKUP job", () => {
		const server = "server { enable_record_transactions: true }";
		const message = 'jobs.system_jobs needs { id: BACKUP, schedule: "@daily", disabled: false }';
		expect(lintTrailbaseConfig(server)).toEqual([message]);
		expect(
			lintTrailbaseConfig(
				`${server} jobs { system_jobs: [{ id: BACKUP, schedule: "@daily", disabled: true }] }`,
			),
		).toEqual([message]);
		expect(
			lintTrailbaseConfig(
				`${server} jobs { system_jobs: [{ id: BACKUP, schedule: "@hourly", disabled: false }] }`,
			),
		).toEqual([message]);
	});

	test("reports a syntax error instead of passing", () => {
		expect(lintTrailbaseConfig(`${base}\nrecord_apis: [{ name: "notes" `)).toEqual([
			"config.textproto: line 5: expected a field name or }, found end of input",
		]);
	});
});

describe("parseTextproto", () => {
	test("reads scalars, nested messages, lists and repeated fields", () => {
		const parsed = parseTextproto(`
# comment with "quotes" and { braces }
name: "a \\"quoted\\" # value" # trailing comment
count: -12.5
flag: true
mode: CREATE
inner: { deep { value: 'single' }; other: 1, }
items: [1, 2]
items: 3
empty: []
`);
		expect(parsed).toEqual(
			new Map<string, TextprotoValue[]>([
				["name", [{ kind: "string", text: 'a "quoted" # value' }]],
				["count", [{ kind: "number", text: "-12.5" }]],
				["flag", [{ kind: "identifier", text: "true" }]],
				["mode", [{ kind: "identifier", text: "CREATE" }]],
				[
					"inner",
					[
						new Map<string, TextprotoValue[]>([
							[
								"deep",
								[
									new Map<string, TextprotoValue[]>([
										["value", [{ kind: "string", text: "single" }]],
									]),
								],
							],
							["other", [{ kind: "number", text: "1" }]],
						]),
					],
				],
				[
					"items",
					[
						{ kind: "number", text: "1" },
						{ kind: "number", text: "2" },
						{ kind: "number", text: "3" },
					],
				],
				["empty", []],
			]),
		);
	});

	test.each([
		["name:", "line 1: expected a value, found end of input"],
		['name: "open', "line 1: unterminated string"],
		["name: @", "line 1: unexpected character '@'"],
		["a { b: 1", "line 1: expected a field name or }, found end of input"],
		["}", "line 1: expected a field name, found '}'"],
		["a: [1 2]", "line 1: expected , or ], found '2'"],
		["a\nb", "line 2: expected : or { after a, found 'b'"],
	])("rejects %p", (text, message) => {
		expect(() => parseTextproto(text)).toThrow(message);
	});
});
