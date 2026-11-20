import { decoders as d, orNull, type Decoded } from "@/api/index.ts";
import {
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
const byName = (x: Decision) => x.decided_by?.name?.trim() || null;

/** The HOLD's one-target line (U109). */
export function holdOneLine(craft: string, name: string, x: Decision): string {
  const by = byName(x);
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
