import { spacecraftCommandingContribution } from "@cadence/commanding/spacecraft-commanding";
import { spacecraftRoutingContribution } from "@cadence/communications/spacecraft-routing";
import {
  SPACECRAFT_PAGE_SLOT,
  type SpacecraftPageContribution,
} from "@cadence/plugin-sdk/spacecraft-pages";
import type { Component } from "vue";

export function admitSpacecraftPages(items: readonly SpacecraftPageContribution<Component>[]) {
  const entries = new Map<string, SpacecraftPageContribution<Component>>();
  for (const item of items) {
    if (
      item.slot !== SPACECRAFT_PAGE_SLOT ||
      item.version !== 1 ||
      !/^[a-z][a-z0-9.-]+$/.test(item.id) ||
      entries.has(item.id) ||
      typeof item.read !== "function"
    ) {
      throw new Error("Invalid spacecraft page contribution.");
    }
    entries.set(item.id, Object.freeze({ ...item }));
  }
  return Object.freeze(Object.fromEntries(entries));
}
export const spacecraftModulePages = admitSpacecraftPages([
  spacecraftRoutingContribution,
  spacecraftCommandingContribution,
]);
