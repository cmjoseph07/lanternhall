import { describe, expect, test } from "bun:test";
import { platformModule } from "../module";
import { describeModuleGraphError, type ModuleManifest, validateModuleGraph } from "./module-graph";

// Synthetic manifests: real optional modules do not exist yet.
const core: ModuleManifest = { id: "core-a", kind: "core", dependsOn: [], integratesWith: [] };
const library: ModuleManifest = {
	id: "library",
	kind: "optional",
	dependsOn: ["core-a"],
	integratesWith: [],
};
const shelf: ModuleManifest = {
	id: "shelf",
	kind: "optional",
	dependsOn: ["core-a", "library"],
	integratesWith: [],
};
const reader: ModuleManifest = {
	id: "reader",
	kind: "optional",
	dependsOn: ["library", "shelf", "notes"],
	integratesWith: ["mailer"],
};
const notes: ModuleManifest = { id: "notes", kind: "optional", dependsOn: [], integratesWith: [] };
const mailer: ModuleManifest = {
	id: "mailer",
	kind: "optional",
	dependsOn: [],
	integratesWith: [],
};
const manifests = [core, library, shelf, reader, notes, mailer];

describe("validateModuleGraph", () => {
	test("core modules alone are valid", () => {
		expect(validateModuleGraph([], manifests)).toEqual([]);
	});

	test("an optional module with every dependency enabled is valid; core deps are implicit", () => {
		expect(validateModuleGraph(["library", "shelf"], manifests)).toEqual([]);
	});

	test("a module enabled without its optional dependencies names the missing ids", () => {
		expect(validateModuleGraph(["reader"], manifests)).toEqual([
			{ kind: "missing-dependencies", id: "reader", missing: ["library", "shelf", "notes"] },
		]);
	});

	test("missing dependencies are checked for every enabled module, so gaps deeper down surface", () => {
		expect(validateModuleGraph(["shelf", "reader", "notes"], manifests)).toEqual([
			{ kind: "missing-dependencies", id: "shelf", missing: ["library"] },
			{ kind: "missing-dependencies", id: "reader", missing: ["library"] },
		]);
	});

	test("a dependency with no manifest counts as missing", () => {
		const orphan: ModuleManifest = {
			id: "orphan",
			kind: "optional",
			dependsOn: ["ghost"],
			integratesWith: [],
		};
		expect(validateModuleGraph(["orphan"], [...manifests, orphan])).toEqual([
			{ kind: "missing-dependencies", id: "orphan", missing: ["ghost"] },
		]);
	});

	test("integrations with a disabled module never fail validation", () => {
		expect(validateModuleGraph(["library", "shelf", "notes", "reader"], manifests)).toEqual([]);
	});

	test("an unknown module id is an error", () => {
		expect(validateModuleGraph(["library", "typo"], manifests)).toEqual([
			{ kind: "unknown-module", id: "typo" },
		]);
	});

	test("listing a core module is an error, since core modules are always on", () => {
		expect(validateModuleGraph(["core-a"], manifests)).toEqual([
			{ kind: "core-module-listed", id: "core-a" },
		]);
	});

	test("the platform manifest is a core module with no dependencies", () => {
		expect(platformModule).toEqual({
			id: "platform",
			kind: "core",
			dependsOn: [],
			integratesWith: [],
		});
		expect(validateModuleGraph([], [platformModule])).toEqual([]);
	});
});

describe("describeModuleGraphError", () => {
	test("names the module and every missing id", () => {
		expect(
			describeModuleGraphError({
				kind: "missing-dependencies",
				id: "reader",
				missing: ["library", "notes"],
			}),
		).toBe('"reader" needs "library", "notes" enabled too');
	});

	test("names an unknown id", () => {
		expect(describeModuleGraphError({ kind: "unknown-module", id: "typo" })).toBe(
			'unknown module "typo"',
		);
	});

	test("names a listed core module", () => {
		expect(describeModuleGraphError({ kind: "core-module-listed", id: "core-a" })).toBe(
			'"core-a" is a core module and always on; remove it from the list',
		);
	});
});
