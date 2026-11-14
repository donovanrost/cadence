import type { Component } from "vue";
import OpsActivationRequests from "./OpsActivationRequests.vue";
import OpsAlarms from "./OpsAlarms.vue";
import OpsCommands from "./OpsCommands.vue";
import OpsConsoleLanding from "./OpsConsoleLanding.vue";
import OpsContactDetail from "./OpsContactDetail.vue";
import OpsContactPlanShow from "./OpsContactPlanShow.vue";
import OpsContactRecord from "./OpsContactRecord.vue";
import OpsContactSchedule from "./OpsContactSchedule.vue";
import OpsDataOperations from "./OpsDataOperations.vue";
import OpsDataOperationsManage from "./OpsDataOperationsManage.vue";
import OpsDataSourceRegistration from "./OpsDataSourceRegistration.vue";
import OpsDataSourceSettings from "./OpsDataSourceSettings.vue";
import OpsDataSources from "./OpsDataSources.vue";
import OpsFleetPlanning from "./OpsFleetPlanning.vue";
import OpsFleetPlanningNew from "./OpsFleetPlanningNew.vue";
import OpsFleetPlanningRun from "./OpsFleetPlanningRun.vue";
import OpsTelemetryExplore from "./OpsTelemetryExplore.vue";
import OpsTimeline from "./OpsTimeline.vue";

// Only native route presentation roots belong to this remote registry.
// Feature widgets are reached through their owner's public component tree.
// oxlint-disable typescript/no-unsafe-assignment -- This registry contains SFC constructors checked by vue-tsc.
export const OPS_COMPONENTS: Record<string, Component> = {
  OpsActivationRequests,
  OpsAlarms,
  OpsCommands,
  OpsConsoleLanding,
  OpsContactDetail,
  OpsContactPlanShow,
  OpsContactRecord,
  OpsContactSchedule,
  OpsDataOperations,
  OpsDataOperationsManage,
  OpsDataSourceRegistration,
  OpsDataSourceSettings,
  OpsDataSources,
  OpsFleetPlanning,
  OpsFleetPlanningNew,
  OpsFleetPlanningRun,
  OpsTelemetryExplore,
  OpsTimeline,
};
// oxlint-enable typescript/no-unsafe-assignment

export const OPS_COMPONENT_NAMES = Object.freeze(Object.keys(OPS_COMPONENTS).sort());
