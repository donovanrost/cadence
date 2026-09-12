import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { setupEnvelope } from "../../shared/mission-form-port";
import { readForm } from "./form-validation";
import MissionTransportCreation from "./MissionTransportCreation.vue";
export const setupPages = [
  {
    id: "comms.transport-new",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "New Transport",
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: MissionTransportCreation,
    actions: ["validate", "save"],
    read(value, context) {
      const envelope = setupEnvelope(value),
        model = readForm(envelope.model, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected resource identity.");
      return { model, context: { missionId: context.missionId }, phase: envelope.phase };
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
