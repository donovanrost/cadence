import { commandHistoryContribution } from "@cadence/commanding/command-history";
import { queueSubmissionContribution } from "@cadence/commanding/queue-submission";
import { commandStagesContribution } from "@cadence/commanding/command-stages";
import { stageCreateContribution } from "@cadence/commanding/stage-create";
import { stageWorkbenchContribution } from "@cadence/commanding/stage-workbench";
import { commandAuthoringContribution } from "@cadence/commanding/command-authoring";
import { commandReviewContribution } from "@cadence/commanding/command-review";
import { alarmConditionsContribution } from "@cadence/limits-and-alarming/alarm-conditions";
import { sourceContributions } from "@cadence/data-operations/data-sources";
import {
  historicalWorkflowsContribution,
  historicalWorkflowsManageContribution,
} from "@cadence/data-operations/historical-workflows";
import {
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
} from "@cadence/planning-and-contacts/contact-scheduling";
import {
  requirementTemplateContribution,
  requirementDeclarationContribution,
  requirementDirectoryContribution,
  requirementReviewContribution,
} from "@cadence/planning-and-contacts/contact-requirements";
import { fleetPolicyContribution } from "@cadence/planning-and-contacts/fleet-planning";
import { planReviewContribution } from "@cadence/planning-and-contacts/contact-plans";
import { directoryContribution } from "@cadence/dashboards-and-exploration/directory";
import { commandMonitorContribution } from "@cadence/commanding/mission-commands";
import { executionDiagnosticsContribution } from "@cadence/dashboards-and-exploration/execution-diagnostics";
import { explorationContribution } from "@cadence/dashboards-and-exploration/exploration";
import { creationContribution } from "@cadence/dashboards-and-exploration/creation";
import { workspaceContribution } from "@cadence/dashboards-and-exploration/workspace";
import { editorContribution } from "@cadence/dashboards-and-exploration/editor";
import { activityContribution } from "@cadence/dashboards-and-exploration/activity";
import { settingsContribution } from "@cadence/dashboards-and-exploration/settings";
import {
  shareContribution,
  snapshotContribution,
} from "@cadence/dashboards-and-exploration/sharing";
import { libraryContribution } from "@cadence/dashboards-and-exploration/library";
import {
  playlistsContribution,
  playlistPresentationContribution,
} from "@cadence/dashboards-and-exploration/playlists";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import type { Component } from "vue";
import {
  fleetDirectoryContribution,
  fleetStartContribution,
  fleetRunContribution,
} from "@cadence/planning-and-contacts/fleet-planning";
export const opsPages: Record<string, OpsPageContribution<Component>> = {
  [commandStagesContribution.id]: commandStagesContribution,
  [stageCreateContribution.id]: stageCreateContribution,
  [stageWorkbenchContribution.id]: stageWorkbenchContribution,
  [commandAuthoringContribution.id]: commandAuthoringContribution,
  [alarmConditionsContribution.id]: alarmConditionsContribution,
  ...Object.fromEntries(sourceContributions.map((c) => [c.id, c])),
  [historicalWorkflowsContribution.id]: historicalWorkflowsContribution,
  [historicalWorkflowsManageContribution.id]: historicalWorkflowsManageContribution,
  [contactScheduleContribution.id]: contactScheduleContribution,
  [contactRecordContribution.id]: contactRecordContribution,
  [reservationContribution.id]: reservationContribution,

  [planReviewContribution.id]: planReviewContribution,
  [requirementTemplateContribution.id]: requirementTemplateContribution,
  [requirementDeclarationContribution.id]: requirementDeclarationContribution,
  [requirementDirectoryContribution.id]: requirementDirectoryContribution,
  [requirementReviewContribution.id]: requirementReviewContribution,
  [fleetPolicyContribution.id]: fleetPolicyContribution,
  [fleetStartContribution.id]: fleetStartContribution,
  [fleetRunContribution.id]: fleetRunContribution,
  [fleetDirectoryContribution.id]: fleetDirectoryContribution,
  [commandHistoryContribution.id]: commandHistoryContribution,
  [commandMonitorContribution.id]: commandMonitorContribution,
  [commandReviewContribution.id]: commandReviewContribution,
  [queueSubmissionContribution.id]: queueSubmissionContribution,
  [explorationContribution.id]: explorationContribution,
  [executionDiagnosticsContribution.id]: executionDiagnosticsContribution,
  [directoryContribution.id]: directoryContribution,
  [creationContribution.id]: creationContribution,
  [workspaceContribution.id]: workspaceContribution,
  [editorContribution.id]: editorContribution,
  [activityContribution.id]: activityContribution,
  [settingsContribution.id]: settingsContribution,
  [shareContribution.id]: shareContribution,
  [snapshotContribution.id]: snapshotContribution,
  [libraryContribution.id]: libraryContribution,
  [playlistsContribution.id]: playlistsContribution,
  [playlistPresentationContribution.id]: playlistPresentationContribution,
};
