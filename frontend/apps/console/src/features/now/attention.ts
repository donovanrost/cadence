import { decoders as d, type Decoded } from "@/api/index.ts";
import type { QueueItem } from "./queue.ts";
import { plural } from "@/ui";
import { attentionUplinkReader, reasonSentence } from "@/features/contacts/readiness.ts";

/**
 * Attention items in Now's queue (U31, DECISIONS #54; ops.md §action-queue `attention`): mission
 * "needs acknowledgment" items, for now pass-resolution conflicts. One row each, never grouped;
 * the pass's contact drawer holds the detail and the actions.
 */

const who = d.object({ kind: d.token, id: d.nullable(d.token), name: d.nullable(d.string) });

export const attentionReader = d.object({
  id: d.token,
  source: d.token,
  /** null on uplink_blocked (U33). */
  conflict: d.nullable(d.token),
  state: d.oneOf(["open", "acknowledged"] as const),
  acknowledged_by: d.nullable(who),
  // d2632794: cancel_failed/late_confirmation may have no contact; reservation_id is the pass
  // row id, which the Contacts drawer selects on.
  contact_id: d.nullable(d.token),
  reservation_id: d.optional(d.token),
  station: d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
  provider: d.object({ id: d.nullable(d.token), name: d.nullable(d.string) }),
  starts_at: d.timestamp,
  raised_at: d.timestamp,
  provider_message: d.nullable(d.string),
  /** U33 uplink_blocked only; null (or absent) on pass_resolution. */
  uplink: d.optional(d.nullable(attentionUplinkReader)),
  resolution: d.nullable(
    d.object({
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
  action: d.optional(d.nullable(d.string)),
  resolved_at: d.timestamp,
});

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

/** Title tail and evidence sentence (U31 copy). Unknown conflicts still say who and where. */
export function attentionWords(a: Attention): Readonly<{ what: string; evidence: string }> {
  const provider = a.provider.name ?? "The provider";
  if (a.uplink) {
    // U33: "EARENDIL-001 · Can't command on the SVB-1 pass." / "<reason>. 2 command groups are queued for it."
    const n = a.uplink.command_group_ids.length;
    const station = a.station.code ?? a.station.name ?? "this";
    return {
      what: `Can't command on the ${station} pass.`,
      evidence: `${reasonSentence(a.uplink.reason)}.${n ? ` ${plural(n, "command group")} ${n === 1 ? "is" : "are"} queued for it.` : ""}`,
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
      return {
        what: `${provider} disagrees with this pass's booking.`,
        evidence: "Review the contact before counting on it.",
      };
  }
}

/** Meta before the live AOS countdown: station code, and who acknowledged (U21). */
export function attentionMeta(a: Attention): string | null {
  const parts = [
    a.station.code ?? a.station.name,
    a.state === "acknowledged" ? `Ack ${a.acknowledged_by?.name ?? ""}`.trim() : null,
  ].filter((p): p is string => Boolean(p));
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

export type Resolved = Decoded<typeof resolvedReader>;

/**
 * What closed it (ops.md §resolved, U32): a person reads "Resolved by Mira K."; a provider
 * "Resolved: Northlight confirmed"; the system its action alone ("Resolved: cancel confirmed").
 * Never "by Cadence".
 */
export function resolvedWords(r: Resolved): string {
  const action = r.action ? noStop(r.action.replaceAll("_", " ")) : null;
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
  const live = new Set(current.map((r) => r.key));
  return resolved.flatMap((r) => {
    const index = previous.findIndex((p) => p.key === r.id);
    const prev = previous[index];
    if (!prev || live.has(r.id) || already.some((f) => f.item.key === `${r.id}|resolved`))
      return [];
    const item: QueueItem = {
      ...prev,
      key: `${r.id}|resolved`,
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
