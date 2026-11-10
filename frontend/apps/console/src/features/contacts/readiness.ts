import { decoders as d, request, type ApiError, type Decoded } from "@/api/index.ts";
import type { OpState } from "@/ui";

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

const passRef = d.object({
  reservation_id: d.token,
  contact_id: d.nullable(d.token),
  station: d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
  starts_at: d.timestamp,
});

/** On command groups: the pass the group is queued for, and its readiness. */
export const groupUplinkReader = d.object({
  pass: passRef,
  /** 12792cb2: the next ready pass it would go on; named only when present. */
  next_pass: d.optional(d.nullable(passRef)),
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

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

export type ReadinessTag = Readonly<{ state: OpState; label: string; sentence: string | null }>;

/**
 * The pass's readiness tag (U33). `where: "drawer"` also says "Uplink ready"; bars and rows stay
 * quiet when ready. null readiness (no live uplink session, 9f4e947b) shows nothing.
 */
export function readinessTag(
  r: Readonly<{ state: string; reason: string | null; since: string | null }> & {
    command_groups_queued?: number;
  },
  where: "drawer" | "row",
): ReadinessTag | null {
  const since = r.since ? ` since ${hhmm(r.since)}` : "";
  switch (r.state) {
    case "ready":
      return where === "drawer"
        ? { state: "nominal", label: "Uplink ready", sentence: null }
        : null;
    case "qualifying":
      return {
        state: "neutral",
        label: "Uplink qualifying…",
        sentence: since ? `Qualifying${since}.` : null,
      };
    case "recovering":
      return {
        state: "neutral",
        label: "Uplink recovering…",
        sentence: since ? `Recovering${since}.` : null,
      };
    case "blocked":
      return {
        state: (r.command_groups_queued ?? 1) > 0 ? "crit" : "caution",
        label: "Can't command",
        sentence: `Can't command: ${reasonClause(r.reason)}.`,
      };
    default:
      return null;
  }
}

/**
 * A command group's line when its pass is blocked (U33): "Can't command on the SVB-1 pass (AOS
 * 00:54Z): <reason>. Nothing will be sent on this pass until the uplink recovers. Otherwise it goes
 * on the next ready pass unless it expires at 03:00Z." null unless blocked.
 */
export function groupBlockedLine(
  uplink: GroupUplink | null | undefined,
  expiresAt: string | null,
): string | null {
  if (!uplink || uplink.readiness.state !== "blocked") return null;
  const station = uplink.pass.station.code ?? uplink.pass.station.name ?? "its";
  const next = uplink.next_pass ?? null;
  return [
    `Can't command on the ${station} pass (AOS ${hhmm(uplink.pass.starts_at)}): ${reasonClause(uplink.readiness.reason)}.`,
    "Nothing will be sent on this pass until the uplink recovers.",
    `Otherwise it goes on the next ready pass${next ? ` (${next.station.code ?? next.station.name ?? "next"} ${hhmm(next.starts_at)})` : ""}${expiresAt ? ` unless it expires at ${hhmm(expiresAt)}` : ""}.`,
  ].join(" ");
}

const recovered = d.object({ state: d.token, ready_at: d.nullable(d.timestamp) });

export type RecoverOutcome = Readonly<{ tone: "nominal" | "info" | "caution"; text: string }>;

/** `Recover uplink` (U33): re-runs the automatic recovery; audited and safe to repeat, so no confirm. */
export async function recoverUplink(missionId: string, passId: string): Promise<RecoverOutcome> {
  const r = await request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}/recover-uplink`,
    recovered,
    { method: "POST" },
  );
  if (r.ok)
    return r.value.state === "ready"
      ? {
          tone: "nominal",
          text: `Uplink recovered${r.value.ready_at ? ` · ready at ${hhmm(r.value.ready_at)}` : ""}.`,
        }
      : { tone: "info", text: "Recovering now." };
  return recoverErrorWords(r.error);
}

export function recoverErrorWords(e: ApiError): RecoverOutcome {
  const code = "code" in e ? e.code : null;
  if (code === "uplink_recovery_refused") {
    const details = "details" in e ? e.details : null;
    const reason =
      typeof details === "object" &&
      details !== null &&
      "reason" in details &&
      typeof details.reason === "string"
        ? details.reason
        : null;
    return {
      tone: "caution",
      text: `Recovery refused: ${reason ? reasonClause(reason) : "no reason given"}.`,
    };
  }
  if (code === "uplink_not_blocked")
    return { tone: "info", text: "The uplink isn't blocked any more." };
  if (code === "uplink_recovering") return { tone: "info", text: "Recovering now." };
  if (e.kind === "forbidden")
    return { tone: "caution", text: "Operators with mission access can recover the uplink." };
  if (e.kind === "unavailable" || e.kind === "malformed")
    return {
      tone: "caution",
      text: "No answer from the server, so recovery may or may not have started. Reload the pass to check.",
    };
  const message = "message" in e ? e.message : "the server didn't say why";
  return { tone: "caution", text: `Nothing changed: ${message.replace(/[.!?]+$/, "")}.` };
}
