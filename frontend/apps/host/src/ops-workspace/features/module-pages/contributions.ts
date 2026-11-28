import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import type { Component } from "vue";
export const opsPages = createPageRegistry<OpsPageContribution<Component>>("ops.page", {
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
});
