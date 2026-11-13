import { decoders as d, isKnown, type Decoded, type Unrecognized } from "@/api/index.ts";
import type { QueueItem } from "./queue.ts";
import { plural } from "@/ui";
import { formatBytes } from "@/features/catalog/importRun.ts";
import { attentionUplinkReader, reasonSentence } from "@/features/contacts/readiness.ts";

/**
 * Attention items in Now's queue (U31, DECISIONS #54; ops.md §action-queue `attention`): mission
 * "needs acknowledgment" items, for now pass-resolution conflicts. One row each, never grouped;
 * the pass's contact drawer holds the detail and the actions.
 */

/** U32: who closed or acknowledged it. */
const who = d.object({
  kind: d.knownText(["user", "provider", "system"] as const),
  id: d.nullable(d.token),
  name: d.nullable(d.string),
});

/** The attention sources the console words (ops.md §attention, contacts.md U33, #71, U38). */
export const attentionSources = [
  "pass_resolution",
  "uplink_blocked",
  "pass_release",
  "contact_settlement",
  "mission_runtime",
] as const;
/** pass_resolution conflicts (ops.md §attention). */
export const attentionConflicts = [
  "cancel_failed",
  "late_confirmation",
  "contradicts_attestation",
] as const;
/** U38 mission_runtime reason keys (domain 292c8e6b, final). */
export const runtimeReasons = [
  "spec_mismatch",
  "reconcile_crashed",
  "runtime_not_running",
  "apply_failed",
] as const;
/** U37 contact_settlement: why the telemetry isn't stored (null: a slow drain past the deadline). */
export const settlementFailures = ["telemetry_storage_unavailable", "settle_failed"] as const;

/** The server's own key, known or not: attention routes, fold keys. */
export const serverKey = <T extends string>(value: T | Unrecognized): string =>
  isKnown(value) ? value : value.unrecognized;

export const attentionReader = d.object({
  id: d.token,
  source: d.knownText(attentionSources),
  /** null on uplink_blocked (U33). */
  conflict: d.nullable(d.knownText(attentionConflicts)),
  state: d.oneOf(["open", "acknowledged"] as const),
  acknowledged_by: d.nullable(who),
  // d2632794: cancel_failed/late_confirmation may have no contact; reservation_id is the pass
  // row id, which the Contacts drawer selects on.
  contact_id: d.nullable(d.token),
  // Null when a contact has no provider booking (domain, #71).
  reservation_id: d.optional(d.nullable(d.token)),
  // Null on mission-wide sources (mission_runtime: no station, provider or pass).
  station: d.nullable(
    d.object({
      ref: d.nullable(d.string),
      id: d.nullable(d.token),
      // free-text: a station's call sign, not a vocabulary
      code: d.nullable(d.string),
      name: d.nullable(d.string),
    }),
  ),
  provider: d.nullable(d.object({ id: d.nullable(d.token), name: d.nullable(d.string) })),
  starts_at: d.nullable(d.timestamp),
  raised_at: d.timestamp,
  provider_message: d.nullable(d.string),
  /** U33 uplink_blocked only; null (or absent) on pass_resolution. */
  uplink: d.optional(d.nullable(attentionUplinkReader)),
  /** pass_release only (api-ops, ahead of domain): what happened to the Release's cancel. */
  release: d.optional(
    d.nullable(
      d.object({
        // contacts.md §release: refused | not_sent | unknown (no answer yet).
        outcome: d.knownText(["refused", "not_sent", "unknown"] as const),
        // free-text: the provider's own reason sentence
        reason: d.nullable(d.string),
      }),
    ),
  ),
  /** contact_settlement (#71): telemetry still on disk, not yet in the TSDB; null elsewhere. */
  backlog: d.optional(
    d.nullable(
      d.object({
        entries: d.integer,
        bytes: d.integer,
        journals: d.integer,
        /** Journal off (domain 96307ac5): batches that were in memory when the runtime stopped. */
        queued: d.optional(d.nullable(d.integer)),
        /** true: those batches are gone, not on disk (U37 journal off). */
        lost: d.optional(d.nullable(d.boolean)),
      }),
    ),
  ),
  /** mission_runtime (U38): the reason key, generations, and when the mismatch began. */
  reason: d.optional(d.nullable(d.knownText(runtimeReasons))),
  desired_generation: d.optional(d.nullable(d.integer)),
  applied_generation: d.optional(d.nullable(d.integer)),
  since: d.optional(d.nullable(d.timestamp)),
  change_set_id: d.optional(d.nullable(d.token)),
  activated_at: d.optional(d.nullable(d.timestamp)),
  /** enabled | disabled: whether the mission keeps a disk copy of incoming telemetry. */
  journal: d.optional(d.nullable(d.knownText(["enabled", "disabled"] as const))),
  ends_at: d.optional(d.timestamp),
  deadline_at: d.optional(d.nullable(d.timestamp)),
  /** telemetry_storage_unavailable | settle_failed | null (a slow drain past the deadline). */
  failure_kind: d.optional(d.nullable(d.knownText(settlementFailures))),
  failure_message: d.optional(d.nullable(d.string)),
  /** automatic | manual (domain #71 replay: manual after 6 failed replays, operator retries). */
  retry: d.optional(d.nullable(d.knownText(["automatic", "manual"] as const))),
  attempts: d.optional(d.nullable(d.integer)),
  /** Set while automatic and backing off (5 min doubling to 2 h); null when manual. */
  next_attempt_at: d.optional(d.nullable(d.timestamp)),
  last_attempt_at: d.optional(d.nullable(d.timestamp)),
  resolution: d.nullable(
    d.object({
      // free-text: what the operator recorded doing (resolve's action_text, contacts.md)
      action: d.token,
      actor: who,
      at: d.timestamp,
      note: d.nullable(d.string),
      provider_reference: d.nullable(d.string),
    }),
  ),
});
export type Attention = Decoded<typeof attentionReader>;

/** Attention items resolved in the last 60 s; `id` is the row's item id (fafe581a). */
export const resolvedReader = d.object({
  id: d.token,
  resolved_by: who,
  // free-text: an open phrase or key ("uplink recovered", "replayed"); known keys get words (U32)
  action: d.optional(d.nullable(d.string)),
  resolved_at: d.timestamp,
});

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short: `18:49Z`, with the date when it isn't today. */
export const short = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;

/**
 * U37 evidence by failure_kind: what's on disk and why it isn't stored. Never "TSDB", "journal" or
 * "settlement"; the storage outage's own message stays out of the line (Technical details).
 */
export function settlementEvidence(f: SettlementFacts, now: Date = new Date()): string {
  if (f.lost) return lostEvidence(f.queued);
  const one = f.backlog.entries === 1;
  const disk = `${f.backlog.entries.toLocaleString("en-US")} ${one ? "entry" : "entries"} (${formatBytes(f.backlog.bytes)}) ${one ? "is" : "are"} on disk`;
  const them = one ? "it" : "them";
  if (f.retry === "manual") {
    // ux 294e67c6: replay stopped after MAX_TRIES; the reason is the last try's.
    const why =
      f.failureKind === "telemetry_storage_unavailable"
        ? `telemetry storage was unavailable at the last try${f.lastAttemptAt ? `, ${short(f.lastAttemptAt, now)}` : ""}`
        : f.failureMessage
          ? noStop(f.failureMessage)
          : null;
    return `${disk}. Cadence stopped after ${f.attempts ?? MAX_TRIES} failed tries${why ? `: ${why}` : ""}.`;
  }
  const failed = f.attempts ? `${f.attempts} of ${MAX_TRIES} tries failed.` : null;
  const next = f.nextAttemptAt
    ? Date.parse(f.nextAttemptAt) <= now.getTime()
      ? "Trying now."
      : `Next try at ${short(f.nextAttemptAt, now)}.`
    : null;
  const tail = [failed, next].filter(Boolean).join(" ");
  const end = tail ? ` ${tail}` : "";
  if (f.failureKind === null)
    return `${disk}, past the ${f.deadline ? `${f.deadline} ` : ""}deadline for storing ${them}.${end}`;
  if (f.failureKind === "telemetry_storage_unavailable")
    return next
      ? `${disk}. Telemetry storage is unavailable.${end}`
      : `${disk}. Telemetry storage is unavailable; Cadence stores ${them} when it's back.${end}`;
  return `${disk}. Cadence couldn't store ${them}${f.failureMessage ? `: ${noStop(f.failureMessage)}` : ""}.${end}`;
}

/**
 * U37 journal off (ux 4f8b796c): never "on disk", never Retry. `queued` null: the count is unknown.
 */
export function lostEvidence(queued: number | null): string {
  if (queued === null)
    return "Telemetry in memory when the runtime stopped wasn't stored. This mission doesn't keep a disk copy, so it can't be recovered.";
  const one = queued === 1;
  return `${queued.toLocaleString("en-US")} telemetry ${one ? "batch was" : "batches were"} in memory when the runtime stopped and ${one ? "wasn't" : "weren't"} stored. This mission doesn't keep a disk copy, so ${one ? "it" : "they"} can't be recovered.`;
}

/** Replay stops after this many failed tries and hands to an operator (director, #71). */
export const MAX_TRIES = 6;

export type SettlementFacts = Readonly<{
  backlog: Readonly<{ entries: number; bytes: number }>;
  /** Journal off: the batches are gone (U37); `queued` counts them. */
  lost: boolean;
  queued: number | null;
  failureKind: NonNullable<Attention["failure_kind"]> | null;
  failureMessage: string | null;
  /** `00:57Z`; null on a folded line (ux 3f61ef71). */
  deadline: string | null;
  retry: NonNullable<Attention["retry"]> | null;
  attempts: number | null;
  nextAttemptAt: string | null;
  lastAttemptAt: string | null;
}>;

/** One item's facts for the evidence line. */
export const settlementFacts = (a: Attention & { backlog: NonNullable<Attention["backlog"]> }) =>
  ({
    backlog: a.backlog,
    lost: a.backlog.lost === true,
    queued: a.backlog.queued ?? null,
    failureKind: a.failure_kind ?? null,
    failureMessage: a.failure_message ?? null,
    deadline: a.deadline_at ? hhmm(a.deadline_at) : null,
    retry: a.retry ?? null,
    attempts: a.attempts ?? null,
    nextAttemptAt: a.next_attempt_at ?? null,
    lastAttemptAt: a.last_attempt_at ?? null,
  }) satisfies SettlementFacts;

const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

/** Title tail and evidence sentence (U31 copy). Unknown conflicts still say who and where. */
export function attentionWords(
  a: Attention,
  now: Date = new Date(),
): Readonly<{ what: string; evidence: string }> {
  const provider = a.provider?.name ?? "The provider";
  if (a.release) {
    // A Release whose cancel the provider refused or didn't answer: the booking may still stand.
    const what =
      a.release.outcome === "refused"
        ? `${provider} refused the cancel`
        : a.release.outcome === "not_sent"
          ? "the cancel wasn't sent"
          : `no answer from ${provider} to the cancel`;
    const why = a.release.reason ?? a.provider_message;
    return {
      what: `Release not confirmed: ${what}.`,
      evidence: `${why ? `${noStop(why)}. ` : ""}The pass may still be booked and billed.`,
    };
  }
  if (a.backlog) {
    // U37 (#71 contact_settlement): system-closed, no person action, no Acknowledge.
    const station = a.station?.code ?? a.station?.name;
    return {
      what: `Telemetry from the ${station ? `${station} ` : ""}${a.starts_at ? `${short(a.starts_at, now)} ` : ""}pass ${a.backlog.lost ? "was lost" : "isn't stored yet"}.`,
      evidence: settlementEvidence(settlementFacts({ ...a, backlog: a.backlog }), now),
    };
  }
  if (a.uplink) {
    // U33: "EARENDIL-001 · Can't command on the SVB-1 pass." / "<reason>. 2 command groups are queued for it."
    const n = a.uplink.command_group_ids.length;
    const station = a.station?.code ?? a.station?.name ?? "this";
    return {
      what: `Can't command on the ${station} pass.`,
      evidence: `${reasonSentence(a.uplink.reason, { provider: a.provider?.name ?? null })}.${n ? ` ${plural(n, "command group")} ${n === 1 ? "is" : "are"} queued for it.` : ""}`,
    };
  }
  const r = a.resolution;
  const by = r ? ` by ${r.actor.name ?? "an operator"} ${hhmm(r.at)}` : "";
  switch (a.conflict) {
    case "contradicts_attestation":
      return {
        what: `${provider} says a pass marked booked isn't.`,
        evidence: `Marked booked${by}${r?.provider_reference ? ` with ref ${r.provider_reference}` : ""}. Don't count on this contact.`,
      };
    case "late_confirmation":
      return {
        what: `${provider} confirmed a pass marked not booked.`,
        evidence: `Marked not booked${by}. It may be booked and billed.`,
      };
    case "cancel_failed":
      return {
        what: `${provider} didn't accept the cancel.`,
        evidence: `${a.provider_message ? `${noStop(a.provider_message)}. ` : ""}The pass may still be booked and billed.`,
      };
    case null:
    default:
      // A source this console doesn't know yet says only that the contact needs a look.
      return a.source === "pass_resolution"
        ? {
            what: `${provider} disagrees with this pass's booking.`,
            evidence: "Review the contact before counting on it.",
          }
        : { what: "This contact needs attention.", evidence: "Review the contact." };
  }
}

/** Meta before the live AOS countdown: station code, and who acknowledged (U21). */
export function attentionMeta(a: Attention, now: Date = new Date()): string | null {
  // U37: `SVA · Northlight · 18:49Z–18:57Z`, dropping any null part (U20).
  if (a.backlog) {
    const window = a.starts_at
      ? `${short(a.starts_at, now)}${a.ends_at ? `–${short(a.ends_at, now)}` : ""}`
      : null;
    return [a.station?.code ?? a.station?.name, a.provider?.name, window]
      .filter((p): p is string => Boolean(p))
      .join(" · ")
      .toUpperCase();
  }
  const parts = [
    a.station?.code ?? a.station?.name,
    a.state === "acknowledged" ? `Ack ${a.acknowledged_by?.name ?? ""}`.trim() : null,
  ].filter((p): p is string => Boolean(p));
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

export type Resolved = Decoded<typeof resolvedReader>;

/** Server actions that read better in words: U37's system 'replayed' = the telemetry got stored. */
const ACTION_WORDS: Readonly<Record<string, string>> = {
  replayed: "telemetry stored",
  // U38: the runtime caught up with the active configuration.
  applied: "configuration applied",
};

/**
 * What closed it (ops.md §resolved, U32): a person reads "Resolved by Mira K."; a provider
 * "Resolved: Northlight confirmed"; the system its action alone ("Resolved: cancel confirmed").
 * Never "by Cadence".
 */
export function resolvedWords(r: Resolved): string {
  const said = r.action ? (ACTION_WORDS[r.action] ?? r.action.replaceAll("_", " ")) : null;
  const action = said ? noStop(said) : null;
  const name = r.resolved_by.name ? noStop(r.resolved_by.name) : null;
  if (r.resolved_by.kind === "user") return `Resolved by ${name ?? "an operator"}.`;
  if (r.resolved_by.kind === "provider")
    return `Resolved: ${[name ?? "the provider", action].filter(Boolean).join(" ")}.`;
  return action ? `Resolved: ${action}.` : "Resolved.";
}

/** How long a resolved row stays, faded, before it leaves (U31). */
export const RESOLVED_FADE_MS = 5_000;

export type Fading = Readonly<{ item: QueueItem; index: number; until: number }>;

/**
 * Rows to fade after a read: a row seen last time, now gone, and listed in `resolved` reads
 * "Resolved by Mira K." for 5 s at its old place. It never takes the primary action.
 */
export function newlyResolved(
  previous: readonly QueueItem[],
  current: readonly QueueItem[],
  resolved: readonly Resolved[],
  already: readonly Fading[],
  now: number,
): Fading[] {
  const live = new Set(current.flatMap((r) => [r.key, ...(r.memberKeys ?? [])]));
  const seen = new Set(already.map((f) => f.item.key));
  return resolved.flatMap((r) => {
    // A folded row (U37) fades only once none of its members is still on screen.
    const index = previous.findIndex((p) => p.key === r.id || p.memberKeys?.includes(r.id));
    const prev = previous[index];
    if (!prev) return [];
    const key = `${prev.key}|resolved`;
    const members = prev.memberKeys ?? [prev.key];
    if (live.has(prev.key) || members.some((k) => live.has(k)) || seen.has(key)) return [];
    seen.add(key);
    const { list: _list, memberKeys: _members, ...rest } = prev;
    const item: QueueItem = {
      ...rest,
      key,
      state: "off",
      sentence: resolvedWords(r),
      meta: null,
      acknowledged: true,
    };
    return [{ item, index, until: now + RESOLVED_FADE_MS }];
  });
}

/** Current rows with the fading ones put back where they were. */
export function withFading(rows: readonly QueueItem[], fading: readonly Fading[]): QueueItem[] {
  const out = [...rows];
  for (const f of [...fading].sort((a, b) => a.index - b.index))
    out.splice(Math.min(f.index, out.length), 0, f.item);
  return out;
}
