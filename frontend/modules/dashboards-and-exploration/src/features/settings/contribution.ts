import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardSettings from "./DashboardSettings.vue";
import { settingsActions } from "./contracts";
import { readSettingsState } from "./validation";
export const settingsContribution = {
  id: "dashboards.settings",
  slot: "ops.page",
  version: 1,
  title: "Dashboard settings",
  component: DashboardSettings,
  actions: settingsActions,
  read(value, context) {
    return { state: readSettingsState(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
