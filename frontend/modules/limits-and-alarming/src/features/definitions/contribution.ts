import DefinitionsSurface from "./DefinitionsSurface.vue";
export const definitionsContribution = {
  id: "limits-and-alarming.definitions",
  version: 1,
  applicationKey: "limits",
  surfaceId: "manage",
  query: { id: "cadence.limits.manage", version: 1 },
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: DefinitionsSurface,
} as const;
