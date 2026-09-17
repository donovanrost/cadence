import type { SettingsContext, SettingsSectionDefinition } from "@cadence/plugin-sdk/settings";
export const settingsContext: SettingsContext = {
  actorId: "operator-1",
  organizationId: "organization-1",
  organizationName: "Aster Mission Systems",
  scope: "mission",
  missionId: "mission-1",
  missionName: "Kestrel",
};
export const settingsMetadata: readonly SettingsSectionDefinition[] = [
  {
    id: "cadence.governance",
    slot: "settings.section",
    version: 1,
    scopes: ["organization", "mission"],
    title: "Governance",
    description: "How configuration changes become active.",
    owner: { kind: "host", label: "Cadence" },
  },
  {
    id: "commanding.defaults",
    slot: "settings.section",
    version: 1,
    scopes: ["organization", "mission"],
    title: "Commanding",
    description: "Defaults for preparing commands in the workspace.",
    owner: { kind: "application", applicationKey: "ops_console", label: "Commanding" },
  },
];
export function settingsValue(scope: SettingsContext["scope"] = "mission") {
  return {
    token: "a".repeat(64),
    version: 0,
    saved: scope === "organization" ? { approval_requirement: "independent" } : null,
    effective: { approval_requirement: "independent" },
    organization_default: { approval_requirement: "independent" },
    source: scope === "organization" ? "organization" : "inherited",
    allow_override: true,
    missions: [{ id: "mission-1", name: "Kestrel", override: null }],
    missions_total: 1,
  };
}
export function settingsFixture(
  context = settingsContext,
  sectionId = "cadence.governance",
  value: unknown = settingsValue(context.scope),
) {
  return {
    version: 1,
    status: "ready",
    token: "settings-page-token",
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    data: {
      section_id: sectionId,
      sections: settingsMetadata,
      can_edit: true,
      settings: value,
      history: [],
    },
  };
}
