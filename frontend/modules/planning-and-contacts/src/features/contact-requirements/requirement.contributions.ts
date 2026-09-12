import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import RequirementDirectoryContribution from "./RequirementDirectoryContribution.vue";
import RequirementReviewContribution from "./RequirementReviewContribution.vue";
import { admitRequirementDirectory } from "./requirement-directory";
import { admitRequirementPage } from "./requirement-workflow";
export const requirementDirectoryContribution = {
  id: "planning.requirement-directory",
  slot: "ops.page",
  version: 1,
  title: "Contact Requirements",
  component: RequirementDirectoryContribution,
  query: true,
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected directory resource");
    const directory = admitRequirementDirectory(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!directory) throw Error("Unavailable requirement directory");
    return { directory };
  },
} as const satisfies OpsPageContribution<Component>;
export const requirementReviewContribution = {
  id: "planning.requirement-review",
  slot: "ops.page",
  version: 1,
  title: "Requirement Review",
  component: RequirementReviewContribution,
  query: true,
  actions: ["plan", "create-plan"],
  read(value, context) {
    if (!context.resourceId) throw Error("Missing requirement resource");
    const page = admitRequirementPage(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
      requirement_id: context.resourceId,
    });
    if (!page) throw Error("Unavailable requirement review");
    return { page };
  },
} as const satisfies OpsPageContribution<Component>;
