/**
 * A module's manifest (`src/features/<id>/module.ts`).
 * Core modules are always on; optional modules are switched on in the install config.
 */
export type ModuleManifest = {
	id: string;
	kind: "core" | "optional";
	/** Modules that must be on for this one to work. */
	dependsOn: readonly string[];
	/** Modules that switch on extra features here when enabled; never required. */
	integratesWith: readonly string[];
};

export type ModuleGraphError =
	| { kind: "unknown-module"; id: string }
	| { kind: "core-module-listed"; id: string }
	| { kind: "missing-dependencies"; id: string; missing: string[] };

/** Checks the optional modules listed in the install config; an empty list means valid. */
export function validateModuleGraph(
	enabled: readonly string[],
	manifests: readonly ModuleManifest[],
): ModuleGraphError[] {
	const byId = new Map(manifests.map((manifest) => [manifest.id, manifest]));
	const isOn = (id: string): boolean => {
		const manifest = byId.get(id);
		return manifest !== undefined && (manifest.kind === "core" || enabled.includes(id));
	};

	return enabled.flatMap((id): ModuleGraphError[] => {
		const manifest = byId.get(id);
		if (manifest === undefined) {
			return [{ kind: "unknown-module", id }];
		}
		if (manifest.kind === "core") {
			return [{ kind: "core-module-listed", id }];
		}
		const missing = manifest.dependsOn.filter((dependency) => !isOn(dependency));
		return missing.length === 0 ? [] : [{ kind: "missing-dependencies", id, missing }];
	});
}

export function describeModuleGraphError(error: ModuleGraphError): string {
	switch (error.kind) {
		case "unknown-module":
			return `unknown module "${error.id}"`;
		case "core-module-listed":
			return `"${error.id}" is a core module and always on; remove it from the list`;
		case "missing-dependencies":
			return `"${error.id}" needs ${error.missing.map((id) => `"${id}"`).join(", ")} enabled too`;
	}
}
