import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import PlanReviewContribution from "./PlanReviewContribution.vue";
import { admitPlanReviewPage, planReviewActions } from "./plan-review";
export const planReviewContribution = {
  id: "planning.plan-review",
  slot: "ops.page",
  version: 1,
  title: "Contact Plan Review",
  component: PlanReviewContribution,
  query: true,
  actions: planReviewActions,
  read(value, context) {
    if (!context.resourceId) throw Error("Missing reviewed plan");
    const page = admitPlanReviewPage(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
      plan_id: context.resourceId,
    });
    if (!page) throw Error("Unavailable plan review");
    return { page };
  },
} as const satisfies OpsPageContribution<Component>;
