import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DashboardEditor from "./DashboardEditor.vue";
import { editorActions } from "./contracts";
import { readEditor } from "./validation";
export const editorContribution = {
  id: "dashboards.editor",
  slot: "ops.page",
  version: 1,
  title: "Dashboard editor",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: DashboardEditor,
  actions: [...editorActions, "search_observables"],
  read(value, context) {
    return { state: readEditor(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
