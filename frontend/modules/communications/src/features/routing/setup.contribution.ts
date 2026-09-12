import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { setupEnvelope } from "../../shared/mission-form-port";
import { readForm } from "./form-validation";
import MissionRoutingCreation from "./MissionRoutingCreation.vue";
export const setupPages = [
  {
    id: "comms.routing-new",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "New Routing Rule",
    component: MissionRoutingCreation,
    actions: ["validate", "save"],
    read(value, context) {
      const envelope = setupEnvelope(value),
        model = readForm(envelope.model, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected resource identity.");
      return { model, context: { missionId: context.missionId }, phase: envelope.phase };
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
