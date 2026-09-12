import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandAuthoringPage from "./CommandAuthoringPage.vue";
import { readAuthoringContribution } from "./contracts";
export const commandAuthoringContribution = {
  id: "commanding.authoring",
  slot: "ops.page",
  version: 1,
  title: "Create command request",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: CommandAuthoringPage,
  query: true,
  actions: ["preview", "create"],
  read(value, context) {
    return { page: readAuthoringContribution(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
