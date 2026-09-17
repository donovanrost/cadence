import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandWorkspacePage from "./CommandWorkspacePage.vue";
import { readWorkspace, writeEvents } from "./contracts";
export const commandWorkspaceContribution = {
  id: "commanding.workspace",
  slot: "ops.page",
  version: 1,
  title: "Commanding",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: CommandWorkspacePage,
  query: "live",
  guardNavigation: true,
  actions: ["browse", "catalog_page", "preview_targets", "preview_batch", ...writeEvents],
  read(value, context) {
    return { page: readWorkspace(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
