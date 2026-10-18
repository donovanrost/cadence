import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
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
export const spacecraftModulePages = createPageRegistry<SpacecraftPageContribution<Component>>(
  "spacecraft.page",
  {
    "comms.spacecraft-routing": () =>
      import("@cadence/communications/spacecraft-routing").then(
        (module) => module.spacecraftRoutingContribution,
      ),
    "commanding.spacecraft": () =>
      import("@cadence/commanding/spacecraft-commanding").then(
        (module) => module.spacecraftCommandingContribution,
      ),
  },
  admitSpacecraftPages,
);
