import DefinitionsSurface from "./DefinitionsSurface.vue";
export const definitionsContribution = {
  id: "derived-telemetry.definitions",
  version: 1,
  applicationKey: "derived_telemetry",
  surfaceId: "manage",
  query: { id: "cadence.derived_telemetry.manage", version: 1 },
  actionId: "save_definition",
  component: DefinitionsSurface,
} as const;
