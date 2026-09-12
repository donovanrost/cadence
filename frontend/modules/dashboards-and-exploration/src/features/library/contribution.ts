import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardLibrary from "./DashboardLibrary.vue";
import { libraryActions } from "./contracts";
import { readLibrary } from "./validation";
export const libraryContribution = {
  id: "dashboards.library",
  slot: "ops.page",
  version: 1,
  title: "Dashboard library",
  component: DashboardLibrary,
  actions: libraryActions,
  read(value, context) {
    return { state: readLibrary(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
