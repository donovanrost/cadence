import {
  readSettingsSectionDefinition,
  type SettingsContext,
  type SettingsSectionDefinition,
} from "@cadence/plugin-sdk/settings";
import { array, boolean, count, instant, object, record, string } from "../shell/snapshot-readers";
const historyRow = object({ id: string, version: count, actor: string, saved_at: instant });
export type SettingsHistoryEntry = ReturnType<typeof historyRow>;
export type SettingsAction = {
  token: string;
  revisionToken: string;
  document: Readonly<Record<string, unknown>>;
};
export function readSettingsPage(value: unknown, context: SettingsContext, sectionId: string) {
  if (
    !record(value) ||
    value.version !== 1 ||
    !record(value.context) ||
    value.context.organization_id !== context.organizationId ||
    value.context.mission_id !== context.missionId
  )
    throw new Error("Invalid settings scope.");
  if (value.status === "unavailable") return { status: "unavailable" as const };
  if (
    value.status !== "ready" ||
    !record(value.data) ||
    value.data.section_id !== sectionId ||
    typeof value.token !== "string" ||
    !value.token
  )
    throw new Error("Invalid settings page.");
  const sections = array(readSettingsSectionDefinition)(value.data.sections);
  if (
    sections.length > 65 ||
    new Set(sections.map((section) => section.id)).size !== sections.length ||
    sections.some((section) => !section.scopes.includes(context.scope))
  )
    throw new Error("Invalid settings sections.");
  const selected = sections.find((section) => section.id === sectionId);
  if (!selected) throw new Error("Missing settings section.");
  const history = array(historyRow)(value.data.history);
  if (history.length > 10) throw new Error("Invalid settings history.");
  return {
    status: "ready" as const,
    token: value.token,
    sections,
    selected,
    settings: value.data.settings,
    canEdit: boolean(value.data.can_edit),
    history,
  };
}
export function settingsHref(
  context: SettingsContext,
  section: SettingsSectionDefinition | string,
) {
  const id = typeof section === "string" ? section : section.id;
  const base =
    context.scope === "mission"
      ? `/missions/${encodeURIComponent(context.missionId)}/settings`
      : "/settings";
  return `${base}/${encodeURIComponent(id)}`;
}
export function settingsDraftKey(context: SettingsContext, sectionId: string) {
  return JSON.stringify([context.actorId, context.organizationId, context.missionId, sectionId]);
}
