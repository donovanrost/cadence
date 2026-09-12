import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import { readSurfaces } from "./read-surfaces";

export const missionPages = [
  {
    id: "comms.transports",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Transports",
    component: readSurfaces.transports.component,
    read(value, context) {
      const props = readSurfaces.transports.admit(value, context);
      if (context.resourceId !== undefined) throw new Error("Unexpected Communications resource.");
      return props;
    },
  },
  {
    id: "comms.transport",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Transport",
    component: readSurfaces.transport.component,
    read(value, context) {
      const props = readSurfaces.transport.admit(value, context);
      if (!context.resourceId || props.page.data.id !== context.resourceId)
        throw new Error("Invalid Communications resource.");
      return props;
    },
  },
] satisfies readonly MissionPageContribution<Component>[];
