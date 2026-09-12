import { communicationsMissionPages } from "@cadence/communications/mission-pages";
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
        (!Array.isArray(item.actions) ||
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
export const missionModulePages = admitMissionPages(communicationsMissionPages);
