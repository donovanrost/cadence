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
});
