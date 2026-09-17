import { readSettingsSnapshot } from "@cadence/plugin-sdk/settings";
import { readApprovalValue } from "./contracts";
import type { SettingsSectionContribution } from "@cadence/plugin-sdk/settings";
import GovernanceSettings from "./GovernanceSettings.vue";
export const governanceSettings = {
  read: (snapshot) => readSettingsSnapshot(snapshot, readApprovalValue),
  id: "cadence.governance",
  slot: "settings.section",
  version: 1,
  scopes: ["organization", "mission"],
  title: "Governance",
  description: "How configuration changes become active.",
  owner: { kind: "host", label: "Cadence" },
  component: GovernanceSettings,
} satisfies SettingsSectionContribution<typeof GovernanceSettings>;
