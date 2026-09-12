import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import PublishedWorkspacePage from "./PublishedWorkspacePage.vue";
import { readPublicationRequirement } from "../../shared/publication/contracts";
import { readWorkspaceSnapshot } from "./validation";

export const workspaceContribution = {
  id: "dashboards.workspace",
  slot: "ops.page",
  version: 1,
  title: "Dashboard",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: PublishedWorkspacePage,
  actions: [],
  read(value, context) {
    const requirement = readPublicationRequirement(value, context);
    if (requirement) return { requirement, model: null, context };
    const model = readWorkspaceSnapshot(value, context);
    if (model.document_mode !== "published") throw Error("Viewer requires a published document");
    return { requirement: null, model, context };
  },
} as const satisfies OpsPageContribution<Component>;
