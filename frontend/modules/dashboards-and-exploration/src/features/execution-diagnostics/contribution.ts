import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import PublishedDiagnosticsPage from "./PublishedDiagnosticsPage.vue";
import { readPublicationRequirement } from "../../shared/publication/contracts";
import { readDiagnosticsPage } from "./page-state";
export const executionDiagnosticsContribution = {
  id: "dashboards.execution-diagnostics",
  slot: "ops.page",
  version: 1,
  title: "Execution diagnostics",
  component: PublishedDiagnosticsPage,
  actions: ["inspect"],
  read(value, context) {
    const requirement = readPublicationRequirement(value, context);
    if (requirement) return { requirement, state: null, context };
    return { requirement: null, state: readDiagnosticsPage(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
