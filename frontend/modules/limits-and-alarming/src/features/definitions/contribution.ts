import DefinitionsSurface from "./DefinitionsSurface.vue";
export const definitionsContribution = {
  id: "limits-and-alarming.definitions",
  version: 1,
  applicationKey: "limits",
  surfaceId: "manage",
  query: { id: "cadence.limits.manage", version: 1 },
  component: DefinitionsSurface,
} as const;
