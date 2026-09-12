import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { readSurfaces } from "./read-surfaces";

export const missionPages = [
  {
    id: "comms.ground-stations",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Ground Stations",
    component: readSurfaces.ground_stations.component,
    read(value, context) {
      const props = readSurfaces.ground_stations.admit(value, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected Communications resource.");
      return props;
    },
  },
  {
    id: "comms.ground-station",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Ground Station",
    component: readSurfaces.ground_station.component,
    read(value, context) {
      const props = readSurfaces.ground_station.admit(value, context);
      if (!context.resourceId || props.page.data.id !== context.resourceId)
        throw new Error("Invalid Communications resource.");
      return props;
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
