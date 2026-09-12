import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import FleetStartContribution from "./FleetStartContribution.vue";
import FleetRunContribution from "./FleetRunContribution.vue";
import { admitFleetStart } from "./fleet-start";
import { admitFleetRun } from "./fleet-run";

export const fleetStartContribution = {
  id: "planning.fleet-start",
  slot: "ops.page",
  version: 1,
  title: "Plan Fleet Horizon",
  // Oxlint cannot resolve the SFC constructor; vue-tsc checks the public component contract.
  // oxlint-disable-next-line typescript/no-unsafe-assignment
  component: FleetStartContribution,
  query: true,
  actions: ["validate-fleet-run", "create-fleet-run"],
  read(value, context) {
    if (context.resourceId !== undefined) throw Error("Unexpected fleet start resource.");
    const start = admitFleetStart(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!start) throw Error("Unavailable fleet start.");
    return { start };
  },
} as const satisfies OpsPageContribution<Component>;

export const fleetRunContribution = {
  id: "planning.fleet-run",
  slot: "ops.page",
  version: 1,
  title: "Fleet Planning Run",
  // Oxlint cannot resolve the SFC constructor; vue-tsc checks the public component contract.
  // oxlint-disable-next-line typescript/no-unsafe-assignment
  component: FleetRunContribution,
  query: true,
  actions: ["refresh-fleet-run", "repair-fleet-run"],
  read(value, context) {
    const run = admitFleetRun(value, {
      organization_id: context.organizationId,
      mission_id: context.missionId,
    });
    if (!run || !context.resourceId || run.id !== context.resourceId)
      throw Error("Unavailable fleet run.");
    return { run };
  },
} as const satisfies OpsPageContribution<Component>;
