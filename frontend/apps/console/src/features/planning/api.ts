import { decoders, request, type ApiResult, type Decoded } from "@/api";
import { formatCount } from "@/ui";

/** Requested shape: docs/apogee/plans/setup-shapes.md §CP1 (final contract in api/setup.md). */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const summary = object({
  policy: nullable(
    object({
      version: integer,
      mode: oneOf(["advisory", "automatic_submission"]),
      approval_required: boolean,
      activated_at: nullable(timestamp),
      actor: nullable(object({ name: string })),
    }),
  ),
  coverage: object({
    spacecraft_total: integer,
    covered: integer,
    contacts_per_day: nullable(integer),
    uplink_passes_per_day: nullable(integer),
  }),
  templates: array(
    object({
      id: token,
      name: string,
      applies_to: string,
      rule_summary: string,
      priority: oneOf(["routine", "high", "critical"]),
      version: integer,
      spacecraft_count: integer,
    }),
    1000,
  ),
  not_covered: array(object({ group: token, label: string, count: integer }), 500),
  permissions: array(token, 50),
});
export type PlanningSummary = Decoded<typeof summary>;

export function fetchPlanning(
  missionId: string,
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
