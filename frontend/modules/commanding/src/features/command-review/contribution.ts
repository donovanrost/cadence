import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import CommandReview from "./CommandReview.vue";
import { readCommandReviewPage } from "./contracts";
export const commandReviewContribution = {
  id: "commanding.review",
  slot: "ops.page",
  version: 1,
  title: "Command review",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: CommandReview,
  query: true,
  actions: ["decide"],
  read(value, context) {
    return { page: readCommandReviewPage(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
