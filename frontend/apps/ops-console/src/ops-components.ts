import type { Component } from "vue";
import OpsCommands from "./OpsCommands.vue";
import OpsConsoleLanding from "./OpsConsoleLanding.vue";
import OpsDataSourceRegistration from "./OpsDataSourceRegistration.vue";
import OpsDataSourceSettings from "./OpsDataSourceSettings.vue";
import OpsDataSources from "./OpsDataSources.vue";

// Only native route presentation roots belong to this remote registry.
// Feature widgets are reached through their owner's public component tree.
// oxlint-disable typescript/no-unsafe-assignment -- This registry contains SFC constructors checked by vue-tsc.
export const OPS_COMPONENTS: Record<string, Component> = {
  OpsCommands,
  OpsConsoleLanding,
  OpsDataSourceRegistration,
  OpsDataSourceSettings,
  OpsDataSources,
};
// oxlint-enable typescript/no-unsafe-assignment

export const OPS_COMPONENT_NAMES = Object.freeze(Object.keys(OPS_COMPONENTS).sort());
