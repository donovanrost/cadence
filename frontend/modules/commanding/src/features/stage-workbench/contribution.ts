import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import StageWorkbench from "./StageWorkbench.vue";
import { readWorkbenchPage } from "./contracts";
export const stageWorkbenchContribution = {
  id: "commanding.stage-workbench",
  slot: "ops.page",
  version: 1,
  title: "Command stage",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: StageWorkbench,
  query: true,
  actions: [
    "edit_stage",
    "edit_details",
    "cancel_item",
    "preview_item",
    "save_item",
    "preview_batch",
    "submit",
    "restart_draft",
  ],
  read(value, context) {
    return { page: readWorkbenchPage(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
