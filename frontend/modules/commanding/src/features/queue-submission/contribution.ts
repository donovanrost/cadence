import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import QueueSubmission from "./QueueSubmission.vue";
import { readQueuePage } from "./contracts";
export const queueSubmissionContribution = {
  id: "commanding.queue-submission",
  slot: "ops.page",
  version: 1,
  title: "Queue command",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks this SFC constructor.
  component: QueueSubmission,
  query: true,
  actions: ["submit"],
  read(value, context) {
    return { page: readQueuePage(value, context) };
  },
} as const satisfies OpsPageContribution<Component>;
