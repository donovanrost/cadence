import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandHistory from "./CommandHistory.vue";
import { readCommandHistory } from "./contracts";
export const commandHistoryContribution = {
  id: "commanding.history",
  slot: "ops.page",
  version: 1,
  title: "Command history",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: CommandHistory,
  navigation: true,
  read(value, context) {
    return { model: readCommandHistory(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
