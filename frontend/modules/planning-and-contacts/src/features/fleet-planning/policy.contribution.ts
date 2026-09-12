import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import FleetPolicyContribution from "./FleetPolicyContribution.vue";
import { admitPolicyPage, policyActions } from "./fleet-policy";
export const fleetPolicyContribution = {
  id: "planning.fleet-policy",
  slot: "ops.page",
  version: 1,
  title: "Fleet Policy & Automation",
  component: FleetPolicyContribution,
  query: true,
  actions: policyActions,
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected policy resource");
    const page = admitPolicyPage(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!page) throw Error("Unavailable fleet policy");
    return { page };
  },
} as const satisfies OpsPageContribution<Component>;
