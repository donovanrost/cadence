import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import FleetDirectoryContribution from "./FleetDirectoryContribution.vue";
import { admitFleetDirectory } from "./fleet-directory";
export const fleetDirectoryContribution = {
  id: "planning.fleet-directory",
  slot: "ops.page",
  version: 1,
  title: "Fleet Planning",
  // Oxlint cannot resolve the SFC constructor; vue-tsc checks the public component contract.
  // oxlint-disable-next-line typescript/no-unsafe-assignment
  component: FleetDirectoryContribution,
  query: true,
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected fleet directory resource.");
    const directory = admitFleetDirectory(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!directory) throw Error("Unavailable fleet directory.");
    return { directory };
  },
} as const satisfies OpsPageContribution<Component>;
