import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import NativeHistoricalWorkflows from "./NativeHistoricalWorkflows.vue";
import { admitHistoryPage, historyActions } from "./native-contract";
function contribution(mode: "reader" | "manage", id: string) {
  return {
    id,
    slot: "ops.page",
    version: 1,
    title: "Data Operations",
    // Oxlint does not resolve this SFC constructor; vue-tsc checks its public props.
    // oxlint-disable-next-line typescript/no-unsafe-assignment
    component: NativeHistoricalWorkflows,
    query: true,
    actions: historyActions,
    read(value, context) {
      const page = admitHistoryPage(
        value,
        { organization_id: context.organizationId, mission_id: context.missionId },
        mode,
      );
      if (!page) throw Error("Historical workflow evidence is unavailable");
      return { page };
    },
  } satisfies OpsPageContribution<Component>;
}
export const historicalWorkflowsContribution = contribution("reader", "data-operations.history");
export const historicalWorkflowsManageContribution = contribution(
  "manage",
  "data-operations.history-manage",
);
