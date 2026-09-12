import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardCreation from "./DashboardCreation.vue";
import { readCreation } from "./validation";
export const creationContribution = {
  id: "dashboards.creation",
  slot: "ops.page",
  version: 1,
  title: "Create Dashboard",
  component: DashboardCreation,
  actions: ["create"],
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected creation resource");
    return { state: readCreation(value, context.missionId) };
  },
} as const satisfies OpsPageContribution<Component>;
