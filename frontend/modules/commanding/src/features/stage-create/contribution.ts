import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import StageCreate from "./StageCreate.vue";
import { readCreationPage } from "./contracts";
export const stageCreateContribution = {
  id: "commanding.stage-create",
  slot: "ops.page",
  version: 1,
  title: "Create command stage",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: StageCreate,
  query: true,
  actions: ["create"],
  read(value, context) {
    return { page: readCreationPage(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
