import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardActivity from "./DashboardActivity.vue";
import { activityActions } from "./contracts";
import { readActivity } from "./validation";
export const activityContribution = {
  id: "dashboards.activity",
  slot: "ops.page",
  version: 1,
  title: "Dashboard history",
  component: DashboardActivity,
  actions: activityActions,
  read(value, context) {
    return { state: readActivity(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
