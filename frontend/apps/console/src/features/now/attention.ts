import { decoders as d, type Decoded } from "@/api/index.ts";

/**
 * Attention items in Now's queue (U31, DECISIONS #54; ops.md §action-queue `attention`): mission
 * "needs acknowledgment" items, for now pass-resolution conflicts. One row each, never grouped;
 * the pass's contact drawer holds the detail and the actions.
 */

const who = d.object({ kind: d.token, id: d.nullable(d.token), name: d.nullable(d.string) });

export const attentionReader = d.object({
  id: d.token,
  source: d.token,
  conflict: d.token,
  state: d.oneOf(["open", "acknowledged"] as const),
  acknowledged_by: d.nullable(who),
  contact_id: d.token,
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
  resolved_at: d.timestamp,
});

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

/** Title tail and evidence sentence (U31 copy). Unknown conflicts still say who and where. */
export function attentionWords(a: Attention): Readonly<{ what: string; evidence: string }> {
  const provider = a.provider.name ?? "The provider";
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
