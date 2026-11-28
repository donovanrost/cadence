import { plural } from "@/ui";
import { formatBytes } from "@/features/catalog/importRun.ts";
import { reasonSentence } from "@/features/contacts/readiness.ts";
import type { Attention } from "./attentionReader.ts";

/** Attention rows' words: §4 times, U37 settlement evidence, U31 title tails and meta. */

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short: `18:49Z`, with the date when it isn't today. */
export const short = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;

/** How an archive-quarantine item closed when nobody decided (#791): one sentence for the Now row and the Resolved list. */
export const expiredWords = (at: string): string =>
  `Expired at ${at}: nobody retried or discarded it before its retention ran out, so it was never archived.`;

/**
 * U37 evidence by failure_kind: what's on disk and why it isn't stored. Never "TSDB", "journal" or
 * "settlement"; the storage outage's own message stays out of the line (Technical details).
 */
export function settlementEvidence(f: SettlementFacts, now: Date = new Date()): string {
  if (f.lost) return lostEvidence(f.queued);
  const one = f.backlog.entries === 1;
  const disk = `${f.backlog.entries.toLocaleString("en-US")} ${one ? "entry" : "entries"} (${formatBytes(f.backlog.bytes)}) ${one ? "is" : "are"} on disk`;
  const them = one ? "it" : "them";
  // U84: retrying can't help until the fix lands, so no tries and no next try.
  if (f.failureKind === "replay_id_conflict")
    return `${disk}. Cadence can't store ${them} until the stuck processing is fixed.`;
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

/** A sentence without its closing stop. */
export const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

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
    // Worded by their own rows (U37, U38, U41), never through here.
    case "unsettled":
    case "generation_not_applied":
    case "apply_failed":
    case "apply_stalled":
    case "approval_required":
    case "acknowledgment_required":
    case "configuration_failure":
    case "not_started":
    case "missed":
    case "journal_near_full":
    case "frames_dropped":
    case "journal_disk":
    case "quarantined":
    case "listener_refusal":
    case "outcome_unknown":
    case "replay_id_conflict":
    // provider_ephemeris (#972) words its own row.
    case "norad_id_missing":
    case "failed":
    case "not_ready":
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
