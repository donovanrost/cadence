import type { Component } from "vue";
import MissionList from "./features/mission-directory/MissionList.vue";
import MissionNew from "./features/mission-creation/MissionNew.vue";
import MissionOverview from "./features/mission-overview/MissionOverview.vue";
import { assertDirectory } from "./features/mission-directory/validation";
import { assertCreation } from "./features/mission-creation/validation";
import { assertOverview } from "./features/mission-overview/validation";
export const missionPages: Record<
  string,
  { component: Component; validate: (value: unknown) => void }
> = {
  mission_list: { component: MissionList, validate: assertDirectory },
  mission_new: { component: MissionNew, validate: assertCreation },
  mission_overview: { component: MissionOverview, validate: assertOverview },
};
