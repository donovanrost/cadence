import { readSettingsSnapshot } from "@cadence/plugin-sdk/settings";
import { readWorkspaceDefault } from "./features/settings/contracts";
import type { SettingsSectionContribution } from "@cadence/plugin-sdk/settings";
import WorkspaceSettings from "./features/settings/WorkspaceSettings.vue";
export const workspaceSettingsContribution = {
  read: (snapshot) => readSettingsSnapshot(snapshot, readWorkspaceDefault),
  id: "commanding.defaults",
  slot: "settings.section",
  version: 1,
  scopes: ["organization", "mission"],
  title: "Commanding",
  description: "Defaults for preparing commands in the workspace.",
  owner: { kind: "application", applicationKey: "ops_console", label: "Commanding" },
  component: WorkspaceSettings,
} satisfies SettingsSectionContribution<typeof WorkspaceSettings>;
