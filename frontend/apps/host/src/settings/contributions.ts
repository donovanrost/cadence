import type { Component } from "vue";
import type { SettingsSectionContribution } from "@cadence/plugin-sdk/settings";
import { createPageRegistry } from "../shell/module-pages/lazy-pages";
export const settingsSections = createPageRegistry<SettingsSectionContribution<Component>>(
  "settings.section",
  {
    "cadence.governance": () =>
      import("./features/governance/contribution").then((module) => module.governanceSettings),
    "commanding.defaults": () =>
      import("@cadence/commanding/settings").then((module) => module.workspaceSettingsContribution),
  },
);
