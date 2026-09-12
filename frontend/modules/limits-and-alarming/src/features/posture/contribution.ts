import PostureSurface from "./PostureSurface.vue";
export const postureContribution = {
  id: "limits-and-alarming.posture",
  version: 1,
  applicationKey: "limits",
  surfaceId: "activity",
  query: { id: "cadence.limits.activity", version: 1 },
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: PostureSurface,
} as const;
