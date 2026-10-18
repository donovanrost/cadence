import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardPage from "./DashboardPage.vue";
import { pageActions } from "./contracts";
import { readDashboardPage } from "./validation";

/**
 * The Ops dashboard page: live viewer at /dashboards/:id and in-place editor at
 * /dashboards/:id/edit. Live refreshes arrive as page updates from Phoenix.
 */
export const dashboardContribution = {
  id: "dashboards.workspace",
  slot: "ops.page",
  version: 1,
  title: "Dashboard",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration boundary.
  component: DashboardPage,
  actions: pageActions,
  guardNavigation: true,
  read(value, context) {
    return { page: readDashboardPage(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
