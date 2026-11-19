import type { RouteLocationRaw } from "vue-router";
import { actor, decoders as d, type Decoded } from "@/api/index.ts";
import { short } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * U39 change_set_stale (api BACKLOG 8d; ux decisions U39): the active change set holds staged
 * changes, the oldest staged more than 24 h ago. P3, state off, one per mission. The count leads;
 * the time belongs to "the oldest", not to the authors (U29). Review → Setup › Staged changes.
 */
export const changeSetReader = d.object({
  id: d.token,
  state: d.knownText(["open", "in_review"] as const),
  staged_count: d.integer,
  base_revision: d.nullable(d.integer),
  opened_at: d.nullable(d.timestamp),
  oldest_staged_at: d.nullable(d.timestamp),
  submitted_at: d.nullable(d.timestamp),
  authors: d.array(actor, 100),
});
export type ChangeSet = Decoded<typeof changeSetReader>;

/** "Mira K.", "Mira K. and Ana P.", "Mira K., Ana P. and 2 others". */
export function authorWords(authors: ChangeSet["authors"]): string | null {
  const names = authors.flatMap((a) => (a.name ? [a.name] : []));
  const [a, b] = names;
  if (a === undefined) return null;
  if (b === undefined) return a;
  if (names.length === 2) return `${a} and ${b}`;
  const rest = names.length - 2;
  return `${a}, ${b} and ${rest} ${rest === 1 ? "other" : "others"}`;
}

export function changeSetWords(
  c: ChangeSet,
  now: Date,
): Readonly<{ title: string; evidence: string }> {
  const n = c.staged_count;
  const changes = `${n} staged ${n === 1 ? "change" : "changes"}`;
  const by = authorWords(c.authors);
  const stagedBy = `Staged${c.base_revision !== null ? ` on r${c.base_revision}` : ""}${by ? ` by ${by}` : ""}`;
  // "by Ana P." already ends the sentence.
  const staged = stagedBy.endsWith(".") ? stagedBy : `${stagedBy}.`;
  if (c.state === "in_review")
    return {
      title: `${changes} ${n === 1 ? "is" : "are"} waiting for review`,
      evidence: [
        c.submitted_at ? `Sent for review at ${short(c.submitted_at, now)}.` : null,
        staged,
      ]
        .filter(Boolean)
        .join(" "),
    };
  return {
    title: `${changes} ${n === 1 ? "isn't" : "aren't"} applied`,
    evidence: [
      staged,
      c.oldest_staged_at ? `The oldest has waited since ${short(c.oldest_staged_at, now)}.` : null,
    ]
      .filter(Boolean)
      .join(" "),
  };
}

export function changeSetRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  c: ChangeSet,
  now: Date = new Date(),
): QueueItem {
  const to: RouteLocationRaw = { name: "setup.changes" };
  const words = changeSetWords(c, now);
  return {
    ...base,
    key,
    title: words.title,
    titleTo: to,
    sentence: words.evidence,
    // "SINCE 11-11 02:10Z", then the live age (`T+1d 21:44`) from `due`.
    meta: c.oldest_staged_at ? `SINCE ${short(c.oldest_staged_at, now).toUpperCase()}` : null,
    ...(c.oldest_staged_at ? { due: { label: "", at: c.oldest_staged_at } } : {}),
    action: { label: "Review", to },
  };
}
