import {
  readSettingsSectionDefinition,
  SETTINGS_SECTION_SLOT,
  type SettingsSectionDefinition,
} from "@cadence/plugin-sdk/settings";

export type Scenario =
  | "organization"
  | "single-operator"
  | "inherited"
  | "overridden"
  | "enforced"
  | "read-only"
  | "application-unavailable";
export type ScopeKey = "organization" | "kestrel" | "pathfinder";
export type MissionId = Exclude<ScopeKey, "organization">;
export type SectionId = "cadence.governance" | "commanding.defaults";
export type ApprovalMode = "direct" | "independent";
export type Override<T> = { mode: "inherit" } | { mode: "override"; value: T };
export type OrganizationPolicy = { approval: ApprovalMode; allowOverrides: boolean };
export type ShelfMode = "expanded" | "minimized";
export type ActorId = "maya" | "eli";
export const actors = { maya: "Maya Chen", eli: "Eli Navarro" } as const;
export const missions = [
  {
    id: "kestrel",
    name: "Kestrel",
    description: "Earth observation · 3 spacecraft",
    initials: "KE",
  },
  {
    id: "pathfinder",
    name: "Pathfinder",
    description: "Technology demonstrator · 1 spacecraft",
    initials: "PA",
  },
] as const;
export const scopeNames: Record<ScopeKey, string> = {
  organization: "Flight Operations",
  kestrel: "Kestrel",
  pathfinder: "Pathfinder",
};
export const approvalNames: Record<ApprovalMode, string> = {
  direct: "One authorized operator",
  independent: "Independent approval",
};

function studySection(value: unknown): SettingsSectionDefinition & { readonly id: SectionId } {
  const section = readSettingsSectionDefinition(value);
  if (section.id !== "cadence.governance" && section.id !== "commanding.defaults")
    throw new Error("No study editor registered for this settings section.");
  return { ...section, id: section.id };
}

export const sections = [
  studySection({
    id: "cadence.governance",
    slot: SETTINGS_SECTION_SLOT,
    version: 1,
    scopes: ["organization", "mission"],
    title: "Governance",
    description: "How configuration changes become active.",
    owner: { kind: "host", label: "Cadence" },
  }),
  studySection({
    id: "commanding.defaults",
    slot: SETTINGS_SECTION_SLOT,
    version: 1,
    scopes: ["organization", "mission"],
    title: "Commanding",
    description: "Defaults for the command workspace.",
    owner: { kind: "application", applicationKey: "commanding", label: "Commanding" },
  }),
] as const;

export const spacecraftNames: Record<MissionId, string> = {
  kestrel: "KESTREL-02",
  pathfinder: "PATHFINDER-01",
};

export const settingsPath = (scope: ScopeKey, section: SectionId = "cadence.governance") =>
  `${scope === "organization" ? "/settings" : `/missions/${scope}/settings`}/${section}`;
export const activationPath = (mission: MissionId) =>
  `/missions/${mission}/spacecraft/${spacecraftNames[mission]}/changes`;

export function effectiveApproval(policy: OrganizationPolicy, override: Override<ApprovalMode>) {
  if (!policy.allowOverrides) return { value: policy.approval, source: "enforced" as const };
  if (override.mode === "override") return { value: override.value, source: "overridden" as const };
  return { value: policy.approval, source: "inherited" as const };
}
