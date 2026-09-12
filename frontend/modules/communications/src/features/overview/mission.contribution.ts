import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { readSurfaces } from "./read-surfaces";

export const missionPages = [
  {
    id: "comms.overview",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Overview",
    component: readSurfaces.overview.component,
    read(value, context) {
      const props = readSurfaces.overview.admit(value, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected Communications resource.");
      return props;
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
