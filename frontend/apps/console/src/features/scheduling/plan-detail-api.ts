import {
  actor,
  decoders as d,
  request,
  stationId as stationIdReader,
  type ApiResult,
  type Decoded,
  type MissionId,
} from "@/api";
import { listenerOverlapKey } from "@/features/contacts/listenerOverlap.ts";
import { expiredReader, supersededByReader } from "./lifecycle.ts";
import { base, planRow, stationReader } from "./plans-api.ts";
import { repairInfoReader } from "./repair-info.ts";

/** Contracts: docs/apogee/api/scheduling.md §4: one plan in detail, with S2 demand and booking. */

/** One conflict / at-risk entry; fields depend on `code`, so the code-specific ones are optional. */
const planIssue = d.object({
  code: d.known(["selected_contacts_overlap", "station_unavailable", "station_degraded"]),
  snapshot_ids: d.array(d.token),
  spacecraft_id: d.optional(d.nullable(d.token)),
  ground_station_id: d.optional(stationIdReader),
  window_id: d.optional(d.token),
  kind: d.optional(d.known(["outage", "maintenance", "degraded"])),
});

const planRef = d.object({ id: d.token, version: d.integer });
const approvalReader = d.nullable(
  d.object({
    decision: d.oneOf(["approved", "rejected"] as const),
    actor,
    at: d.timestamp,
    // free-text: the reviewer's note
    reason: d.nullable(d.string),
    exceptions: d.array(
      d.object({
        requirement_id: d.token,
        requirement_version: d.nullable(d.integer),
        // free-text: why the admin accepted this gap
        reason: d.string,
      }),
      5_000,
    ),
  }),
);
const submissionReader = d.nullable(
  d.object({
    round: d.integer,
    actor,
    at: d.timestamp,
    note: d.nullable(d.string),
    unchanged: d.boolean,
  }),
);
const previousRoundReader = d.nullable(
  d.object({
    round: d.integer,
    version: d.integer,
    approval: approvalReader,
    acknowledgements: d.array(
      d.object({
        requirement_id: d.token,
        // free-text: the approver's reason for accepting the gap
        reason: d.string,
      }),
      5_000,
    ),
  }),
);
const executionReader = d.nullable(
  d.object({
    requested: d.integer,
    sent: d.integer,
    never_sent: d.integer,
    confirmed: d.integer,
    uncertain: d.integer,
    rejected: d.integer,
    failed: d.integer,
  }),
);

const unconfirmedReader = d.nullable(
  d.object({
    window_ms: d.integer,
    booked: d.integer,
    passes: d.array(
      d.object({
        snapshot_id: d.token,
        // null when the booking has no provider recorded yet (api drift sweep 11-13)
        provider: d.nullable(d.object({ id: d.token, name: d.nullable(d.string) })),
        sent_at: d.timestamp,
      }),
      5_000,
    ),
  }),
);

/** Domain c38bb5de (scheduling.md "Plan detail measures"): LOS → next AOS over the plan's UTC
 * day, edges included; `from`/`to` null only when the day is fully covered. No limit yet. */
export const longestGapReader = d.optional(
  d.nullable(
    d.object({
      seconds: d.integer,
      limit_seconds: d.nullable(d.integer),
      from: d.nullable(d.timestamp),
      to: d.nullable(d.timestamp),
    }),
  ),
);
const freezeProvider = d.object({ id: d.nullable(d.token), name: d.nullable(d.string) });
/** The earliest offer expiry among passes not yet sent (ux: "Next offer expires"); may be past. */
const providerFreezeReader = d.optional(
  d.nullable(
    d.object({
      at: d.timestamp,
      provider: freezeProvider,
      snapshot_id: d.nullable(d.token),
      by_provider: d.optional(
        d.array(d.object({ provider: freezeProvider, at: d.timestamp }), 100),
      ),
    }),
  ),
);

/** Per-pass booking states (api 8e); they add up to the plan's `execution` counts. */
export const bookingStates = [
  "never_sent",
  "confirmed",
  "uncertain",
  "rejected",
  "failed",
] as const;
export type BookingState = (typeof bookingStates)[number];

export const planDetailReader = d.object({
  ...planRow,
  passes: d.array(
    d.object({
      snapshot_id: d.token,
      spacecraft_id: d.nullable(d.token),
      station: stationReader,
      starts_at: d.timestamp,
      ends_at: d.timestamp,
      synthetic: d.boolean,
      locked: d.boolean,
      /** U58 (b), #361: a single-connection listener overlap with another pass; absent before #640. */
      listener_overlap: listenerOverlapKey,
      /** That offer's expiry (domain c38bb5de). */
      expires_at: d.optional(d.nullable(d.timestamp)),
      /**
       * api 8e: this pass's booking in the approved version; null before execution. state is
       * never_sent | confirmed | uncertain | rejected | failed (kept as a token: a new state
       * reads as plain, it doesn't fail the plan). reason `sending` while requesting.
       */
      booking: d.optional(
        d.nullable(
          d.object({
            state: d.knownText(bookingStates),
            // free-text: an open vocabulary (provider codes); words in booking-state.ts with a fallback
            reason: d.optional(d.nullable(d.token)),
            at: d.optional(d.nullable(d.timestamp)),
            /** The provider's own text (ux: appended in quotes). */
            detail: d.optional(d.nullable(d.string)),
            retryable: d.optional(d.nullable(d.boolean)),
            retry_after_seconds: d.optional(d.nullable(d.integer)),
            /** Operator resolutions (operator_not_booked / rejected / not_sent): who and when. */
            resolved: d.optional(
              d.nullable(
                d.object({
                  // api a6aaa60a: kind comes from the error document and may be absent (shared actor).
                  by: actor,
                  at: d.timestamp,
                }),
              ),
            ),
          }),
        ),
      ),
    }),
    5_000,
  ),
  demand: d.object({
    rule_met: d.integer,
    rule_total: d.integer,
    spacecraft: d.array(
      d.object({
        spacecraft_id: d.token,
        rule_met: d.boolean,
        contacts: d.object({ have: d.integer, need: d.nullable(d.integer) }),
        reasons: d.array(d.string),
        longest_gap: longestGapReader,
        /** Requested uplink legs, not confirmed; `need` null until rules carry a count. */
        uplink_passes: d.optional(
          d.nullable(d.object({ have: d.integer, need: d.nullable(d.integer) })),
        ),
      }),
      5_000,
    ),
    rules: d.array(
      d.object({
        requirement_id: d.token,
        version: d.integer,
        spacecraft_id: d.nullable(d.token),
        text: d.string,
        source: d.known(["requirement", "template"]),
        window: d.object({ from: d.nullable(d.timestamp), to: d.nullable(d.timestamp) }),
      }),
      5_000,
    ),
  }),
  provider_freeze: providerFreezeReader,
  unmet: d.array(
    d.object({
      requirement_id: d.token,
      requirement_version: d.integer,
      spacecraft_id: d.nullable(d.token),
      why: d.array(d.string),
    }),
    5_000,
  ),
  /** `selected_contacts_overlap` (spacecraft_id) or `station_unavailable` (station window, U26). Both block. */
  conflicts: d.array(planIssue, 5_000),
  /** `station_degraded`: passes inside a degraded window; a warning only (U26). */
  at_risk: (value: unknown, path?: string) =>
    value === undefined ? [] : d.array(planIssue, 5_000)(value, path),
  /**
   * api cf3cd37a: counts of the approved version's bookings; null before there are any.
   * requested = sent + never_sent; sent = confirmed + uncertain + rejected + failed.
   */
  execution: (value: unknown, path?: string) =>
    value === undefined ? null : executionReader(value, path),
  /** api 97523716: the latest decision on this version (a sent-back plan shows the rejection). */
  /** U36 (api 75e84d5d): the round that submitted this version. */
  submission: (value: unknown, path?: string) =>
    value === undefined ? null : submissionReader(value, path),
  /** U36: the round before (who sent it back, why, and the author's gap reasons then). */
  previous_round: (value: unknown, path?: string) =>
    value === undefined ? null : previousRoundReader(value, path),
  approval: (value: unknown, path?: string) =>
    value === undefined ? null : approvalReader(value, path),
  /** qa #30: the day's repair chain, root first then each applied repair; null on older servers. */
  chain: (value: unknown, path?: string) =>
    value === undefined ? null : d.array(planRef, 100)(value, path),
  /**
   * qa #30: the id of the plan a new Re-plan starts from (latest applied repair, else the root).
   * The server sends a bare id; an `{id, version}` object is accepted too (the doc doesn't say).
   */
  chain_head: (value: unknown, path?: string): string | null => {
    if (value === undefined || value === null) return null;
    return typeof value === "string" ? d.token(value, path) : planRef(value, path).id;
  },
  /** U30 (api b122f667): placed bookings unanswered past the window, on any state; else null. */
  unconfirmed: (value: unknown, path?: string) =>
    value === undefined ? null : unconfirmedReader(value, path),
  /** U73 A10 (api 7a83a958b): the plan's newest version, for an older version's banner. */
  latest_version: d.optional(d.nullable(d.integer)),
  /** U61: the plan that replaced this one (a newer plan for the day); absent on older servers. */
  superseded_by: (value: unknown, path?: string) =>
    value === undefined ? null : supersededByReader(value, path),
  /** U76 (api 1a5976482): what a re-plan started now would cover; optional until it ships. */
  repair: d.optional(d.nullable(repairInfoReader)),
  /**
   * #257 (api): the mission's approval setting at read time. `direct` ("Applies without approval")
   * gives an org admin the one act; `independent`, absent or unknown: Request approval (U97).
   */
  approval_setting: d.optional(d.nullable(d.knownText(["direct", "independent"] as const))),
  /**
   * #273 (api's final shape): the selected passes whose booking window has closed, read before
   * deciding (null: none); `expired_digest` goes back unchanged on approve (opaque, never computed
   * here); `next_expiry_at`: when the server's set next changes (margin applied), for the live line.
   */
  expired: d.optional(expiredReader),
  expired_digest: d.optional(d.string),
  next_expiry_at: d.optional(d.nullable(d.timestamp)),
});
export type PlanDetail = Decoded<typeof planDetailReader>;
export type PlanIssue = PlanDetail["conflicts"][number];
export type PlanPass = PlanDetail["passes"][number];

export function fetchPlan(
  missionId: MissionId,
  planId: string,
  signal?: AbortSignal,
  /** U73 A10: an older version, read-only (`?version=N`); the current one when absent. */
  version?: number | null,
): Promise<ApiResult<PlanDetail>> {
  const q = version != null ? `?version=${version}` : "";
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}${q}`,
    planDetailReader,
    signal ? { signal } : {},
  );
}
