import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandStages from "./CommandStages.vue";
import { readDirectory } from "./contracts";
export const commandStagesContribution = {
  id: "commanding.stages",
  slot: "ops.page",
  version: 1,
  title: "Command stages",
  component: CommandStages,
  navigation: true,
  query: true,
  read(value, context) {
    return { directory: readDirectory(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
