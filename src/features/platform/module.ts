import type { ModuleManifest } from "./shared/module-graph";

export const platformModule: ModuleManifest = {
	id: "platform",
	kind: "core",
	dependsOn: [],
	integratesWith: [],
};
