import type { Component } from "vue";
import OpsActivationRequests from "./OpsActivationRequests.vue";
import OpsAlarms from "./OpsAlarms.vue";
import OpsCommands from "./OpsCommands.vue";
import OpsConsoleLanding from "./OpsConsoleLanding.vue";
import OpsContactDetail from "./OpsContactDetail.vue";
import OpsContactPlanShow from "./OpsContactPlanShow.vue";
import OpsContactRecord from "./OpsContactRecord.vue";
import OpsContactRequirementList from "./OpsContactRequirementList.vue";
import OpsContactRequirementNew from "./OpsContactRequirementNew.vue";
import OpsContactRequirementShow from "./OpsContactRequirementShow.vue";
import OpsContactRequirementTemplate from "./OpsContactRequirementTemplate.vue";
import OpsContactSchedule from "./OpsContactSchedule.vue";
import OpsDashboardActivitySurface from "./OpsDashboardActivitySurface.vue";
import OpsDashboardDiagnostics from "./OpsDashboardDiagnostics.vue";
import OpsDashboardDirectory from "./OpsDashboardDirectory.vue";
import OpsDashboardLibrary from "./OpsDashboardLibrary.vue";
import OpsDashboardNew from "./OpsDashboardNew.vue";
import OpsDashboardPlaylistPresent from "./OpsDashboardPlaylistPresent.vue";
import OpsDashboardPlaylists from "./OpsDashboardPlaylists.vue";
import OpsDashboardSettings from "./OpsDashboardSettings.vue";
import OpsDashboardShare from "./OpsDashboardShare.vue";
import OpsDashboardShow from "./OpsDashboardShow.vue";
import OpsDashboardSnapshot from "./OpsDashboardSnapshot.vue";
import OpsDataOperations from "./OpsDataOperations.vue";
import OpsDataOperationsManage from "./OpsDataOperationsManage.vue";
import OpsDataSourceRegistration from "./OpsDataSourceRegistration.vue";
import OpsDataSourceSettings from "./OpsDataSourceSettings.vue";
import OpsDataSources from "./OpsDataSources.vue";
import OpsFleetPlanning from "./OpsFleetPlanning.vue";
import OpsFleetPlanningNew from "./OpsFleetPlanningNew.vue";
import OpsFleetPlanningPolicy from "./OpsFleetPlanningPolicy.vue";
import OpsFleetPlanningRun from "./OpsFleetPlanningRun.vue";
import OpsTelemetryExplore from "./OpsTelemetryExplore.vue";
import OpsTimeline from "./OpsTimeline.vue";

// Only native route presentation roots belong to this remote registry.
// Feature widgets are reached through their owner's public component tree.
export const OPS_COMPONENTS: Record<string, Component> = {
  OpsActivationRequests,
  OpsAlarms,
  OpsCommands,
  OpsConsoleLanding,
  OpsContactDetail,
  OpsContactPlanShow,
  OpsContactRecord,
  OpsContactRequirementList,
  OpsContactRequirementNew,
  OpsContactRequirementShow,
  OpsContactRequirementTemplate,
  OpsContactSchedule,
  OpsDashboardActivitySurface,
  OpsDashboardDiagnostics,
  OpsDashboardDirectory,
  OpsDashboardLibrary,
  OpsDashboardNew,
  OpsDashboardPlaylistPresent,
  OpsDashboardPlaylists,
  OpsDashboardSettings,
  OpsDashboardShare,
  OpsDashboardShow,
  OpsDashboardSnapshot,
  OpsDataOperations,
  OpsDataOperationsManage,
  OpsDataSourceRegistration,
  OpsDataSourceSettings,
  OpsDataSources,
  OpsFleetPlanning,
  OpsFleetPlanningNew,
  OpsFleetPlanningPolicy,
  OpsFleetPlanningRun,
  OpsTelemetryExplore,
  OpsTimeline,
};

export const OPS_COMPONENT_NAMES = Object.freeze(Object.keys(OPS_COMPONENTS).sort());
