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
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: DashboardLibrary,
  actions: libraryActions,
  read(value, context) {
    return { state: readLibrary(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
