import { decoders as d, isKnown, orNull, type Decoded } from "@/api/index.ts";
import {
  actorInSentence,
  compositionActor,
  compositionInSentence,
  compositionKey,
  isComposed,
  type Composition,
} from "@/features/catalog/composition.ts";
import { formatShort } from "@/ui";

/**
 * U109 "A composition that's no longer approved" (E2, #546; readers first): the facts a withdrawn
 * or rejected revision carries, and the words the command HOLD and Now's attention row share.
 * Every key is optional, so a server before #546 still reads.
 */
export const decidedBy = d.nullable(d.object({ id: orNull(d.string), name: orNull(d.string) }));
export const decisionKind = d.knownText(["withdrawn", "rejected"] as const);

/** A held target's own keys on the model_approval_withdrawn check (spread into per_target). */
export const withdrawnTargetFields = {
  revision_id: d.optional(d.nullable(d.token)),
  kind: d.optional(d.nullable(decisionKind)),
  decided_by: d.optional(decidedBy),
  decided_at: d.optional(d.nullable(d.timestamp)),
  // free-text: the reason the deciding person gave.
  reason_text: d.optional(d.nullable(d.string)),
  composition: compositionKey,
};

/** One withdrawal or rejection, as the HOLD's held target or the attention row carries it. */
export type Decision = Readonly<{
  kind?: Decoded<typeof decisionKind> | null | undefined;
  decided_by?: Decoded<typeof decidedBy> | undefined;
  decided_at?: string | null | undefined;
  reason?: string | null | undefined;
}>;

/**
 * U109: "composition 3" with several catalogs, "catalog rev 4" with one, "this composition" when
 * the console can't tell. Never an id.
 */
export function compositionName(
  c: Composition | null | undefined,
  rev?: Readonly<{ number: number | null }> | null,
): string {
  // isComposed is a type guard; read the layer from `c` itself so its other branch isn't narrowed.
  const composed = isComposed(c) ? c : null;
  if (composed) return compositionInSentence(composed);
  const layer: Composition["imported_layers"][number] | undefined = c?.imported_layers[0];
  const n = rev?.number ?? layer?.catalog_revision?.number ?? null;
  return n === null ? "this composition" : `catalog rev ${n}`;
}

const at = (iso: string | null | undefined) => (iso ? ` at ${formatShort(new Date(iso))}` : "");
/** The quoted reason, or nothing: with none the sentence ends at the time (U109, as U65). */
const why = (reason: string | null | undefined) => {
  const r = reason?.trim();
  return r ? `: “${r.replace(/[.!?]+$/, "")}”` : "";
};
const rejected = (x: Decision) => x.kind === "rejected";
/** ca-ux on #632: a decision kind this console doesn't know reads neutrally, never as withdrawn. */
const unknownKind = (x: Decision) => x.kind != null && !isKnown(x.kind);
const since = (iso: string | null | undefined) =>
  iso ? ` since ${formatShort(new Date(iso))}` : "";
const byName = (x: Decision) => x.decided_by?.name?.trim() || null;

/** The HOLD's one-target line (U109). */
export function holdOneLine(craft: string, name: string, x: Decision): string {
  const by = byName(x);
  if (unknownKind(x))
    return `${craft} is on ${name}, which is no longer approved${since(x.decided_at)}. Acknowledge the HOLD to send this request to ${craft} anyway.`;
  const what = rejected(x)
    ? by
      ? `which ${by} rejected${at(x.decided_at)}`
      : `which was rejected${at(x.decided_at)}`
    : by
      ? `whose approval ${by} withdrew${at(x.decided_at)}`
      : `whose approval was withdrawn${at(x.decided_at)}`;
  return `${craft} is on ${name}, ${what}${why(x.reason)}. Acknowledge the HOLD to send this request to ${craft} anyway.`;
}

/** "A, B and C", or "A, B, C and 2 more" past three (U109). */
export function craftList(names: readonly string[], max = 3): string {
  if (names.length <= 1) return names[0] ?? "";
  if (names.length > max) return `${names.slice(0, max).join(", ")} and ${names.length - max} more`;
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1) ?? ""}`;
}

/** The HOLD's several-target line (U109). */
export const holdSeveralLine = (held: readonly string[], targets: number) =>
  `${held.length} of the ${targets} targets are on a composition that's no longer approved: ${craftList(held)}. Acknowledge the HOLD to send this request to them anyway.`;

/** The ack note's placeholder (U109). */
export const holdPlaceholder = (held: number) =>
  `Why it's safe to command ${held === 1 ? "it" : "them"}`;

/** The attention row's decision line, without its way out (U109). */
export function decisionLine(x: Decision): string {
  if (unknownKind(x)) return `No longer approved${since(x.decided_at)}.`;
  const by = byName(x);
  const head = rejected(x) ? "Rejected" : "Approval withdrawn";
  return `${head}${by ? ` by ${by}` : ""}${at(x.decided_at)}${why(x.reason)}.`;
}

/**
 * U109's way out: an earlier approved version left (stage a new configuration to move to it), or
 * none (move to an approved composition). `undefined` (a server before D3) says neither.
 */
export function wayOut(name: string, earlier: unknown): string | null {
  if (earlier === undefined) return null;
  return earlier === null
    ? "Move it to an approved composition."
    : `Stage a new configuration to move it to ${name}'s earlier approved version.`;
}

/**
 * E2 (#546, #1042; the release panel's caution): a target whose craft runs a withdrawn revision
 * that its waiting uplinks' GO didn't know about. An unattended release refuses those uplinks; a
 * person naming the contact is not refused, so this cautions them.
 */
export const withdrawnAfterGoReader = d.object({
  revision_id: d.token,
  decision: d.object({
    kind: decisionKind,
    /** The deciding person, as the workspace's approval_withdrawn names them; null with none. */
    by: d.nullable(compositionActor),
    at: d.timestamp,
    // free-text: the deciding person's reason, quoted as written (U65).
    reason: d.nullable(d.string),
  }),
});
export type WithdrawnAfterGo = Decoded<typeof withdrawnAfterGoReader>;

/** The group's own: how many targets are flagged across the whole group, and the newest decision. */
export const groupWithdrawnAfterGoReader = d.nullable(
  d.object({ count: d.integer, latest: withdrawnAfterGoReader }),
);
export type GroupWithdrawnAfterGo = NonNullable<Decoded<typeof groupWithdrawnAfterGoReader>>;

/**
 * The release panel's caution (E2): "The model's approval was withdrawn after GO on 3 spacecraft,
 * latest by Ana R. at 11-27 10:02Z: “Wrong TM table”. Their uplinks won't go out on their own:
 * resubmit for a new GO, or release on a contact you name." A rejection says rejected; a decision
 * kind this console doesn't know says only that it's no longer approved.
 */
export function withdrawnAfterGoLine(w: GroupWithdrawnAfterGo): string {
  const x = w.latest.decision;
  const who = actorInSentence(x.by);
  const on = w.count === 1 ? "on 1 spacecraft" : `on ${w.count} spacecraft, latest`;
  const head = !isKnown(x.kind)
    ? `The model that ${w.count === 1 ? "1 spacecraft runs" : `${w.count} spacecraft run`} is no longer approved${since(x.at)}`
    : `The model's approval was ${x.kind === "rejected" ? "rejected" : "withdrawn"} after GO ${on}${who ? ` by ${who}` : ""}${at(x.at)}${why(x.reason)}`;
  const them = w.count === 1 ? "Its uplinks" : "Their uplinks";
  return `${head}. ${them} won't go out on their own: resubmit for a new GO, or release on a contact you name.`;
}

/** A flagged target's tag (E2): the word beside its stage. */
export const WITHDRAWN_AFTER_GO_TAG = "Approval withdrawn after GO";
