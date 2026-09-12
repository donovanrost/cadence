import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import NativeHistoricalWorkflows from "./NativeHistoricalWorkflows.vue";
import { admitHistoryPage, historyActions } from "./native-contract";
function contribution(mode: "reader" | "manage", id: string): OpsPageContribution<Component> {
  return {
    id,
    slot: "ops.page",
    version: 1,
    title: "Data Operations",
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
  };
}
export const historicalWorkflowsContribution = contribution("reader", "data-operations.history");
export const historicalWorkflowsManageContribution = contribution(
  "manage",
  "data-operations.history-manage",
);
