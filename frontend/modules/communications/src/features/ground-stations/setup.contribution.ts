import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { setupEnvelope } from "../../shared/mission-form-port";
import { readForm, readEditForm } from "./form-validation";
import MissionGroundStationEditor from "./MissionGroundStationEditor.vue";
export const setupPages = [
  {
    id: "comms.ground-station-new",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "New Ground Station",
    component: MissionGroundStationEditor,
    actions: ["validate", "save"],
    read(value, context) {
      const envelope = setupEnvelope(value),
        model = readForm(envelope.model, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected resource identity.");
      return { model, context: { missionId: context.missionId }, phase: envelope.phase };
    },
  },
  {
    id: "comms.ground-station-edit",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Edit Ground Station",
    component: MissionGroundStationEditor,
    actions: ["validate", "save"],
    read(value, context) {
      const envelope = setupEnvelope(value),
        model = readEditForm(envelope.model, context);
      if (!context.resourceId || model.form.fields.ground_station_id.value !== context.resourceId)
        throw new Error("Invalid station identity.");
      return { model, context: { missionId: context.missionId }, phase: envelope.phase };
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
