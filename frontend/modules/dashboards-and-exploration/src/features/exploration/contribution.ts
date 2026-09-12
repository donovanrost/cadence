import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import ExplorationPanel from "./ExplorationPanel.vue";
import { readExploration } from "./validation";
export const explorationContribution = {
  id: "dashboards.exploration",
  slot: "ops.page",
  version: 1,
  title: "Explore",
  component: ExplorationPanel,
  navigation: true,
  read(value, context) {
    return { model: readExploration(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
