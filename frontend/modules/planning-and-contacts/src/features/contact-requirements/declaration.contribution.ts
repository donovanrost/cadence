import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import DeclarationContribution from "./DeclarationContribution.vue";
import { admitDeclarationPage } from "./declaration";
export const requirementDeclarationContribution = {
  id: "planning.requirement-declaration",
  slot: "ops.page",
  version: 1,
  title: "Declare Contact Need",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor; the lint type service cannot resolve Vue modules.
  component: DeclarationContribution,
  query: true,
  actions: ["validate", "save", "spacecraft-page"],
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected declaration resource");
    const page = admitDeclarationPage(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!page) throw Error("Unavailable requirement declaration");
    return { page };
  },
} as const satisfies OpsPageContribution<Component>;
