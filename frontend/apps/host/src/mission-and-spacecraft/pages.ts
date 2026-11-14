import type { Component } from "vue";
import MissionOverview from "./features/mission-overview/MissionOverview.vue";
import { assertOverview } from "./features/mission-overview/validation";
export const missionPages: Record<
  string,
  { component: Component; validate: (value: unknown) => void }
> = {
  mission_overview: { component: MissionOverview, validate: assertOverview },
};
