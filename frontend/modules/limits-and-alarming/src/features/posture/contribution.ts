import PostureSurface from "./PostureSurface.vue";
export const postureContribution = {
  id: "limits-and-alarming.posture",
  version: 1,
  applicationKey: "limits",
  surfaceId: "activity",
  query: { id: "cadence.limits.activity", version: 1 },
  component: PostureSurface,
} as const;
