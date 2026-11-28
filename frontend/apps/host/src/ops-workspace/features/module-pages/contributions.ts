import { createPageRegistry } from "../../../shell/module-pages/lazy-pages";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import type { Component } from "vue";
export const opsPages = createPageRegistry<OpsPageContribution<Component>>("ops.page", {
  "commanding.history": () =>
    import("@cadence/commanding/command-history").then(
      (module) => module.commandHistoryContribution,
    ),
  "commanding.monitor": () =>
    import("@cadence/commanding/mission-commands").then(
      (module) => module.commandMonitorContribution,
    ),
});
