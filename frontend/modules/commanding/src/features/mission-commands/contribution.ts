import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandMonitor from "./CommandMonitor.vue";
import { readCommandMonitor } from "./monitor-validation";
export const commandMonitorContribution = {
  id: "commanding.monitor",
  slot: "ops.page",
  version: 1,
  title: "Commands",
  component: CommandMonitor,
  navigation: true,
  read(value, context) {
    return { model: readCommandMonitor(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
