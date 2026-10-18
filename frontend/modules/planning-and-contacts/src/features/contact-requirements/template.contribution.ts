import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import TemplateContribution from "./TemplateContribution.vue";
import { admitTemplatePage, templateActions } from "./templates";
export const requirementTemplateContribution = {
  id: "planning.requirement-templates",
  slot: "ops.page",
  version: 1,
  title: "Requirement Templates",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor; the lint type service cannot resolve Vue modules.
  component: TemplateContribution,
  query: true,
  actions: templateActions,
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected template resource");
    const page = admitTemplatePage(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!page) throw Error("Unavailable template ledger");
    return { page };
  },
} as const satisfies OpsPageContribution<Component>;
