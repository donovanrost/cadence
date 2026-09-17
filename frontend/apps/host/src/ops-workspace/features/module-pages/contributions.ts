import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import type { Component } from "vue";
export const opsPages = createPageRegistry<OpsPageContribution<Component>>("ops.page", {
  "commanding.workspace": () =>
    import("@cadence/commanding/workspace").then((module) => module.commandWorkspaceContribution),
  "commanding.stages": () =>
    import("@cadence/commanding/command-stages").then((module) => module.commandStagesContribution),
  "commanding.stage-create": () =>
    import("@cadence/commanding/stage-create").then((module) => module.stageCreateContribution),
  "commanding.stage-workbench": () =>
    import("@cadence/commanding/stage-workbench").then(
      (module) => module.stageWorkbenchContribution,
    ),
  "commanding.authoring": () =>
    import("@cadence/commanding/command-authoring").then(
      (module) => module.commandAuthoringContribution,
    ),
  "limits.alarm-conditions": () =>
    import("@cadence/limits-and-alarming/alarm-conditions").then(
      (module) => module.alarmConditionsContribution,
    ),
  "data-operations.sources": async () => {
    const module = await import("@cadence/data-operations/data-sources");
    const entry = module.sourceContributions.find((item) => item.id === "data-operations.sources");
    if (!entry) throw Error("Missing compiled page contribution.");
    return entry;
  },
  "data-operations.source": async () => {
    const module = await import("@cadence/data-operations/data-sources");
    const entry = module.sourceContributions.find((item) => item.id === "data-operations.source");
    if (!entry) throw Error("Missing compiled page contribution.");
    return entry;
  },
  "data-operations.source-registration": async () => {
    const module = await import("@cadence/data-operations/data-sources");
    const entry = module.sourceContributions.find(
      (item) => item.id === "data-operations.source-registration",
    );
    if (!entry) throw Error("Missing compiled page contribution.");
    return entry;
  },
  "data-operations.source-settings": async () => {
    const module = await import("@cadence/data-operations/data-sources");
    const entry = module.sourceContributions.find(
      (item) => item.id === "data-operations.source-settings",
    );
    if (!entry) throw Error("Missing compiled page contribution.");
    return entry;
  },
  "data-operations.history": () =>
    import("@cadence/data-operations/historical-workflows").then(
      (module) => module.historicalWorkflowsContribution,
    ),
  "data-operations.history-manage": () =>
    import("@cadence/data-operations/historical-workflows").then(
      (module) => module.historicalWorkflowsManageContribution,
    ),
  "planning.contact-schedule": () =>
    import("@cadence/planning-and-contacts/contact-scheduling").then(
      (module) => module.contactScheduleContribution,
    ),
  "planning.contact-record": () =>
    import("@cadence/planning-and-contacts/contact-scheduling").then(
      (module) => module.contactRecordContribution,
    ),
  "planning.reservation-review": () =>
    import("@cadence/planning-and-contacts/contact-scheduling").then(
      (module) => module.reservationContribution,
    ),
  "planning.plan-review": () =>
    import("@cadence/planning-and-contacts/contact-plans").then(
      (module) => module.planReviewContribution,
    ),
  "planning.requirement-templates": () =>
    import("@cadence/planning-and-contacts/contact-requirements").then(
      (module) => module.requirementTemplateContribution,
    ),
  "planning.requirement-declaration": () =>
    import("@cadence/planning-and-contacts/contact-requirements").then(
      (module) => module.requirementDeclarationContribution,
    ),
  "planning.requirement-directory": () =>
    import("@cadence/planning-and-contacts/contact-requirements").then(
      (module) => module.requirementDirectoryContribution,
    ),
  "planning.requirement-review": () =>
    import("@cadence/planning-and-contacts/contact-requirements").then(
      (module) => module.requirementReviewContribution,
    ),
  "planning.fleet-policy": () =>
    import("@cadence/planning-and-contacts/fleet-planning").then(
      (module) => module.fleetPolicyContribution,
    ),
  "planning.fleet-start": () =>
    import("@cadence/planning-and-contacts/fleet-planning").then(
      (module) => module.fleetStartContribution,
    ),
  "planning.fleet-run": () =>
    import("@cadence/planning-and-contacts/fleet-planning").then(
      (module) => module.fleetRunContribution,
    ),
  "planning.fleet-directory": () =>
    import("@cadence/planning-and-contacts/fleet-planning").then(
      (module) => module.fleetDirectoryContribution,
    ),
  "commanding.history": () =>
    import("@cadence/commanding/command-history").then(
      (module) => module.commandHistoryContribution,
    ),
  "commanding.monitor": () =>
    import("@cadence/commanding/mission-commands").then(
      (module) => module.commandMonitorContribution,
    ),
  "commanding.review": () =>
    import("@cadence/commanding/command-review").then((module) => module.commandReviewContribution),
  "commanding.queue-submission": () =>
    import("@cadence/commanding/queue-submission").then(
      (module) => module.queueSubmissionContribution,
    ),
  "dashboards.exploration": () =>
    import("@cadence/dashboards-and-exploration/exploration").then(
      (module) => module.explorationContribution,
    ),
  "dashboards.execution-diagnostics": () =>
    import("@cadence/dashboards-and-exploration/execution-diagnostics").then(
      (module) => module.executionDiagnosticsContribution,
    ),
  "dashboards.directory": () =>
    import("@cadence/dashboards-and-exploration/directory").then(
      (module) => module.directoryContribution,
    ),
  "dashboards.creation": () =>
    import("@cadence/dashboards-and-exploration/creation").then(
      (module) => module.creationContribution,
    ),
  "dashboards.workspace": () =>
    import("@cadence/dashboards-and-exploration/workspace").then(
      (module) => module.workspaceContribution,
    ),
  "dashboards.editor": () =>
    import("@cadence/dashboards-and-exploration/editor").then(
      (module) => module.editorContribution,
    ),
  "dashboards.activity": () =>
    import("@cadence/dashboards-and-exploration/activity").then(
      (module) => module.activityContribution,
    ),
  "dashboards.settings": () =>
    import("@cadence/dashboards-and-exploration/settings").then(
      (module) => module.settingsContribution,
    ),
  "dashboards.share": () =>
    import("@cadence/dashboards-and-exploration/sharing").then(
      (module) => module.shareContribution,
    ),
  "dashboards.snapshot": () =>
    import("@cadence/dashboards-and-exploration/sharing").then(
      (module) => module.snapshotContribution,
    ),
  "dashboards.library": () =>
    import("@cadence/dashboards-and-exploration/library").then(
      (module) => module.libraryContribution,
    ),
  "dashboards.playlists": () =>
    import("@cadence/dashboards-and-exploration/playlists").then(
      (module) => module.playlistsContribution,
    ),
  "dashboards.playlist-present": () =>
    import("@cadence/dashboards-and-exploration/playlists").then(
      (module) => module.playlistPresentationContribution,
    ),
});
