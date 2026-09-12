import {
  SPACECRAFT_PAGE_SLOT,
  type SpacecraftPageContribution,
} from "@cadence/plugin-sdk/spacecraft-pages";
import type { Component } from "vue";
import SpacecraftRouting from "./SpacecraftRouting.vue";
import { readSpacecraftRouting } from "./spacecraft-routing.validation";
export const spacecraftRoutingContribution: SpacecraftPageContribution<Component> = Object.freeze({
  id: "comms.spacecraft-routing",
  slot: SPACECRAFT_PAGE_SLOT,
  version: 1,
  title: "Communications routing",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: SpacecraftRouting,
  read: readSpacecraftRouting,
});
