import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardDirectory from "./DashboardDirectory.vue";
import { readDirectory } from "./validation";
export const directoryContribution = {
  id: "dashboards.directory",
  slot: "ops.page",
  version: 1,
  title: "Dashboard Directory",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: DashboardDirectory,
  actions: ["star", "restore"],
  read: (value, context) => {
    if (context.resourceId !== undefined) throw Error("Unexpected directory resource");
    return { state: readDirectory(value, context.missionId) };
  },
} as const satisfies OpsPageContribution<Component>;
