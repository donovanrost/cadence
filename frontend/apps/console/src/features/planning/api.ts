import type { MissionId } from "@/api/index.ts";
import { actor, decoders, request, type ApiResult, type Decoded, type Reader, orNull } from "@/api";
import { formatCount } from "@/ui";

/** Requested shape: docs/apogee/plans/setup-shapes.md §CP1 (final contract in api/setup.md). */
const { array, integer, nullable, object, string, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

/** Template lifecycle (ContactRequirementTemplateRow). */
export const templateStates = ["active", "paused", "closed"] as const;
/** The policy's repair automation (FleetPlanningPolicySchema `automation.mode`), in its labels. */
export const automationModes = ["advisory", "approval_required", "bounded_automatic"] as const;
export const automationWords: Readonly<Record<(typeof automationModes)[number], string>> = {
  advisory: "advise only",
  approval_required: "propose for approval",
  bounded_automatic: "repair automatically (bounded)",
};
/** CP3 template row (also the CP1 summary's `templates`); applies_to / rule_summary are server-made. */
export const templateRow = object({
  id: token,
  name: string,
  state: decoders.known(templateStates),
  version: integer,
  target: raw,
  applies_to: string,
  applies_to_count: integer,
  rule_summary: string,
  priority: token,
});
export type TemplateRow = Decoded<typeof templateRow>;

const summary = object({
  policy: nullable(object({ version: integer, mode: decoders.knownText(automationModes) })),
  coverage: object({
    spacecraft_total: integer,
    covered: integer,
    contacts_per_day: nullable(integer),
    uplink_passes_per_day: nullable(integer),
  }),
  templates: array(templateRow, 1000),
  not_covered: array(
    object({ group: token, label: string, count: integer, suggested_target: nullable(raw) }),
    500,
  ),
  permissions: array(token, 50),
});
export type PlanningSummary = Decoded<typeof summary>;

export function fetchPlanning(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<PlanningSummary>> {
  return request(`/missions/${encodeURIComponent(missionId)}/contact-planning`, summary, {
    signal,
  });
}

export function situation(s: PlanningSummary): string {
  if (s.policy === null) return "Contact planning isn't set up";
  const missing = s.coverage.spacecraft_total - s.coverage.covered;
  return missing === 0
    ? "Every spacecraft has a contact rule"
    : `${formatCount(missing)} spacecraft have no contact rule`;
}

const templateDetail = (value: unknown, path = "") => ({
  ...templateRow(value, path),
  ...object({
    document: raw,
    versions: array(
      object({
        version: integer,
        created_at: decoders.timestamp,
        actor: orNull(actor),
      }),
      500,
    ),
    /** L2 (api agreed 11-13): the last lifecycle move; null while active since create. */
    state_changed: decoders.optional(
      nullable(
        object({
          state: decoders.known(templateStates),
          at: decoders.timestamp,
          actor: orNull(actor),
          // free-text: the reason a person gave for pausing, resuming or closing it.
          reason: nullable(string),
        }),
      ),
    ),
  })(value, path),
});
export type TemplateDetail = ReturnType<typeof templateDetail>;

export function fetchTemplate(
  key: Readonly<{ missionId: MissionId; templateId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<TemplateDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/contact-planning/templates/${encodeURIComponent(key.templateId)}`,
    templateDetail,
    { signal },
  );
}

/** ux (7)/U24: durations in the server's rule sentence as "6h 00m" (it writes "6h00"). */
export function ruleText(summary: string): string {
  return summary.replace(/\b(\d+)h(\d{2})\b/g, "$1h $2m");
}

const collator = new Intl.Collator("en", { numeric: true, sensitivity: "base" });
/** ux (6): templates in natural name order (EARENDIL-002 before EARENDIL-010). */
export function sortedTemplates<T extends { name: string }>(rows: readonly T[]): readonly T[] {
  return [...rows].sort((a, b) => collator.compare(a.name, b.name));
}
