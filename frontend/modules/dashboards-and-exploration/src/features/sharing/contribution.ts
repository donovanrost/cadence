import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import SharedDashboardView from "./SharedDashboardView.vue";
import { readSharedView } from "./validation";
export const shareContribution = {
  id: "dashboards.share",
  slot: "ops.page",
  version: 1,
  title: "Mission share",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: SharedDashboardView,
  actions: [],
  read(value, context) {
    return { model: readSharedView(value, context, "share"), context };
  },
} as const satisfies OpsPageContribution<Component>;
export const snapshotContribution = {
  id: "dashboards.snapshot",
  slot: "ops.page",
  version: 1,
  title: "Definition snapshot",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: SharedDashboardView,
  actions: [],
  read(value, context) {
    return { model: readSharedView(value, context, "snapshot"), context };
  },
} as const satisfies OpsPageContribution<Component>;
