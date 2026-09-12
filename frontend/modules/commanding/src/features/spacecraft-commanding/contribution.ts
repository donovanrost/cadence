import type { Component } from "vue";
import type { SpacecraftPageContribution } from "@cadence/plugin-sdk/spacecraft-pages";
import SpacecraftCommandingPanel from "./SpacecraftCommandingPanel.vue";
import { readSpacecraftCommanding } from "./contracts";
export const spacecraftCommandingContribution = {
  id: "commanding.spacecraft",
  slot: "spacecraft.page",
  version: 1,
  title: "Command interpretation",
  component: SpacecraftCommandingPanel,
  read(value, context) {
    return { model: readSpacecraftCommanding(value, context) };
  },
} as const satisfies SpacecraftPageContribution<Component>;
