import { decoders as d, type Decoded } from "@/api/index.ts";

/**
 * Uplink readiness per pass (ux U33, DECISIONS #58; contacts.md §Uplink readiness). Quiet when
 * ready; a blocked pass says why in words, never the key. No imports from other features, so Now,
 * Contacts and Commands can all read it.
 */

export const readinessStates = ["ready", "qualifying", "recovering", "blocked"] as const;
export type ReadinessState = (typeof readinessStates)[number];

/** On pass rows: null when the pass has no uplink to be ready (downlink-only, not booked). */
export const passReadinessReader = d.object({
  state: d.token,
  reason: d.nullable(d.token),
  since: d.nullable(d.timestamp),
  command_groups_queued: d.integer,
});
export type PassReadiness = Decoded<typeof passReadinessReader>;

/** On command groups: the pass the group is queued for, and its readiness. */
export const groupUplinkReader = d.object({
  pass: d.object({
    reservation_id: d.token,
    contact_id: d.nullable(d.token),
    station: d.object({
      ref: d.nullable(d.string),
      id: d.nullable(d.token),
      code: d.nullable(d.string),
      name: d.nullable(d.string),
    }),
    starts_at: d.timestamp,
  }),
  readiness: d.object({
    state: d.token,
    reason: d.nullable(d.token),
    since: d.nullable(d.timestamp),
  }),
});
export type GroupUplink = Decoded<typeof groupUplinkReader>;

/** On attention items of source uplink_blocked. */
export const attentionUplinkReader = d.object({
  state: d.token,
  reason: d.nullable(d.token),
  since: d.nullable(d.timestamp),
  command_group_ids: d.array(d.token, 1_000),
});

/** Domain's reason keys as sentences (no final stop). Unknown keys fall back to sentence case. */
const REASONS: Readonly<Record<string, string>> = {
  protocol_state_restore_required: "The session needs its protocol state restored",
};

export function reasonSentence(key: string | null): string {
  if (key === null) return "The uplink isn't ready";
  const known = REASONS[key];
  if (known) return known;
  const words = key.replaceAll("_", " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** Mid-sentence form: "Can't command: the session needs its protocol state restored." */
export const reasonClause = (key: string | null) => {
  const s = reasonSentence(key);
  return s.charAt(0).toLowerCase() + s.slice(1);
};
