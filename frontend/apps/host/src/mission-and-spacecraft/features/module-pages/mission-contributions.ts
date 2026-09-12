import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import type { Component } from "vue";

export function admitMissionPages(items: readonly MissionPageContribution<Component>[]) {
  const entries = new Map<string, MissionPageContribution<Component>>();
  for (const item of items) {
    if (
      item.slot !== MISSION_PAGE_SLOT ||
      item.version !== 1 ||
      !/^[a-z][a-z0-9.-]+$/.test(item.id) ||
      entries.has(item.id) ||
      typeof item.read !== "function" ||
      (item.actions !== undefined &&
        (!isArray(item.actions) ||
          new Set(item.actions).size !== item.actions.length ||
          item.actions.some((action) => !/^[a-z][a-z0-9.-]*$/.test(action))))
    ) {
      throw new Error("Invalid mission page contribution.");
    }
    entries.set(
      item.id,
      Object.freeze({
        ...item,
        ...(item.actions ? { actions: Object.freeze([...item.actions]) } : {}),
      }),
    );
  }
  return Object.freeze(Object.fromEntries(entries));
}
export const missionModulePages = createPageRegistry<MissionPageContribution<Component>>(
  "mission.page",
  {
    "comms.overview": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find((item) => item.id === "comms.overview");
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.validation": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.validation",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.transports": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.transports",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.transport": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find((item) => item.id === "comms.transport");
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.routing": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find((item) => item.id === "comms.routing");
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.routing-detail": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.routing-detail",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.ground-stations": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.ground-stations",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.ground-station": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.ground-station",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.transport-new": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.transport-new",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.routing-new": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.routing-new",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.ground-station-new": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.ground-station-new",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.ground-station-edit": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.ground-station-edit",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.provider-list": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.provider-list",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.provider-new": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.provider-new",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
    "comms.provider-show": async () => {
      const module = await import("@cadence/communications/mission-pages");
      const entry = module.communicationsMissionPages.find(
        (item) => item.id === "comms.provider-show",
      );
      if (!entry) throw Error("Missing compiled page contribution.");
      return entry;
    },
  },
  admitMissionPages,
);

// Inspect runtime input without widening the already declared readonly action type to any[].
function isArray(value: unknown): boolean {
  return Array.isArray(value);
}
