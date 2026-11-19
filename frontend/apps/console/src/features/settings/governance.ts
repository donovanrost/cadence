import { isError, type ApiError } from "@/api";
import type { SettingsField, SettingsScope } from "./api.ts";

/**
 * #233 (api's allowed_values / can_inherit; ux U96): who may change a mission's approval setting.
 * The console can't see the viewer's role, so every line is picked from what the read says: the
 * values this viewer may choose, whether they may inherit, and the field's current value.
 */

// compared-as-text: a settings field path, an open set from the governance section's schema
const isApproval = (f: Pick<SettingsField, "path">) => f.path === "approval_requirement";
/** The strictest approval requirement (needs a second person's approval). */
const STRICTEST = "independent";
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
/** The form's text for an enum value (SchemaForm's option value). */
const optionText = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));

/**
 * The approval setting's allowed_values is missing or null in the read (#233 always sends it), so the
 * console can't tell what this viewer may choose. ca-security C1: it fails closed (read-only, no
 * Reset to inherited) rather than offer 'direct'. Presentation only; the server still refuses.
 */
const limitsUnread = (f: SettingsField) =>
  isApproval(f) && (f.allowed_values === undefined || f.allowed_values === null);

/** ux U96 (U86): what the console can't read, with its way out; for the approval setting with its limits missing. */
const UNREAD_LINE =
  "Cadence couldn't read who may change this setting, so it can't be changed here. Reload to try again. If it's still missing, tell the team that runs Cadence for you.";

/** The viewer can't change this field at all (allowed_values [], or the approval setting's limits unread). */
export const readOnly = (f: SettingsField) => f.allowed_values?.length === 0 || limitsUnread(f);

/**
 * Per field, the enum options this viewer can't choose, as SchemaForm option text: shown disabled,
 * not hidden (ux U96 A6). Absent allowed_values limits nothing.
 */
export function disabledValues(
  fields: readonly SettingsField[],
): Readonly<Record<string, readonly string[]>> {
  const out: Record<string, readonly string[]> = {};
  for (const f of fields) {
    const allowed = f.allowed_values;
    if (!allowed || allowed.length === 0 || !f.enum) continue;
    const off = f.enum.filter((o) => !allowed.some((v) => same(v, o.value)));
    if (off.length > 0) out[f.path] = off.map((o) => optionText(o.value));
  }
  return out;
}

/**
 * ux U96: why the approval setting is read-only, by its current value (no role in the read).
 * TODO(#233): only approval_requirement is governed today; a field governed later needs ux's line
 * here too, or its read-only state has no reason (A6).
 */
export function readOnlyHint(f: SettingsField): string | null {
  if (!isApproval(f) || !readOnly(f)) return null;
  if (limitsUnread(f)) return UNREAD_LINE;
  return same(f.value, STRICTEST)
    ? "It's already set to the strictest option. Only an organization admin can loosen it."
    : "Only a mission admin or an organization admin can change this.";
}

/** ux U96: under the form, when an option is shown disabled. */
export const optionsHint = (f: SettingsField): string | null =>
  isApproval(f) && disabledValues([f])[f.path]
    ? "Only an organization admin can let changes apply without approval."
    : null;

/**
 * ux U96 pin: the value comes from the organization and this viewer may set that same value for the
 * mission, so it's kept if the organization's setting changes (api: a mission admin on a mission
 * inheriting independent gets allowed_values [independent]).
 */
export const pinnable = (f: SettingsField) =>
  f.source !== "mission" && (f.allowed_values?.some((v) => same(v, f.value)) ?? false);

/** Setting the inherited value is the viewer's only choice, so Override would offer nothing more. */
export const onlyPin = (f: SettingsField) => pinnable(f) && f.allowed_values?.length === 1;

/** ux U96: the line beside 'Set for <mission>'. */
export const pinLine = (missionName: string) =>
  `${missionName} uses the organization's setting. Set it for ${missionName} to keep it if the organization's setting changes.`;

/** The viewer may clear the mission's value back to the organization's (absent = may, except the
 * approval setting with its limits unread). */
export const canInherit = (f: SettingsField) => f.can_inherit !== false && !limitsUnread(f);

/** ux U96: why Reset to inherited is disabled. TODO(#233): approval-only, as readOnlyHint. */
export const inheritHint = (f: SettingsField, missionName: string): string | null =>
  limitsUnread(f)
    ? UNREAD_LINE
    : isApproval(f) && !canInherit(f)
      ? `The organization's setting lets changes apply without approval, so only an organization admin can switch ${missionName} to it.`
      : null;

/**
 * ux U96: a refused approval-setting save, worded by the level it saved; null for any other failure
 * (the shared failure outcome words it). A mission admin's save at the organization level is a plain
 * 403 forbidden.
 */
export function approvalRefusal(
  error: ApiError,
  scope: SettingsScope["kind"],
  sectionKey: string,
  missionName: string,
): string | null {
  if (isError(error, "approval_policy_change_requires_mission_admin"))
    return "Not saved: only a mission admin or an organization admin can change approval settings.";
  const orgOnly =
    isError(error, "approval_policy_change_requires_organization_admin") ||
    // compared-as-text: a settings section key, an open set from the server's settings registry
    (error.kind === "forbidden" && scope === "organization" && sectionKey === "cadence.governance");
  if (!orgOnly) return null;
  return scope === "mission"
    ? `Not saved: only an organization admin can let changes on ${missionName} apply without approval.`
    : "Not saved: only an organization admin can change the organization's approval setting.";
}

/** ux U96, the enforced case: the governance section's locked line (other sections keep theirs). */
export const lockedLine = (sectionKey: string) =>
  // compared-as-text: a settings section key, an open set from the server's settings registry
  sectionKey === "cadence.governance"
    ? "The organization sets this for every mission, and missions can't change it. An organization admin changes it in the organization's settings."
    : "The organization sets these and doesn't allow missions to override them.";
