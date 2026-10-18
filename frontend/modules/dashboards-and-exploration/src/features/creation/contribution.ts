import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardCreation from "./DashboardCreation.vue";
import { readCreation } from "./validation";
export const creationContribution = {
  id: "dashboards.creation",
  slot: "ops.page",
  version: 1,
  title: "Create Dashboard",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: DashboardCreation,
  actions: ["create"],
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected creation resource");
    return { state: readCreation(value, context.missionId) };
  },
} as const satisfies OpsPageContribution<Component>;
