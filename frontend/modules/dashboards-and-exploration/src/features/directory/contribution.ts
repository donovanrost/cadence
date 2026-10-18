import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardDirectory from "./DashboardDirectory.vue";
import { directoryActions } from "./contracts";
import { readDirectoryPage } from "./validation";

/**
 * The mission's dashboard directory. Filters live in the URL; actions are
 * sequenced; changes by other sessions arrive as page updates from Phoenix.
 */
export const directoryContribution = {
  id: "dashboards.directory",
  slot: "ops.page",
  version: 1,
  title: "Dashboards",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration boundary.
  component: DashboardDirectory,
  actions: directoryActions,
  read(value, context) {
    return { page: readDirectoryPage(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
