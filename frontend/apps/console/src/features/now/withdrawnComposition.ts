import type { RouteLocationRaw } from "vue-router";
import { decoders as d } from "@/api/index.ts";
import { compositionKey } from "@/features/catalog/composition.ts";
import {
  compositionName,
  decidedBy,
  decisionKind,
  decisionLine,
  wayOut,
} from "@/features/commands/groups/withdrawn.ts";
import type { Attention } from "./attention.ts";
import type { Member } from "./actionQueueReader.ts";
import type { QueueItem } from "./queue.ts";

/**
 * Now's row for a craft on a composition that's no longer approved (U109, E2 #546; ca-engineer's
 * shape 11-20): kind attention, source model_approval_withdrawn, its own facts nested in
 * `withdrawal`. P1/P2 is the server's (a pass within 2 h or in progress); nothing to acknowledge,
 * it leaves when the craft runs an approved revision.
 */
const catalogRevision = d.nullable(
  d.object({
    id: d.token,
    number: d.nullable(d.integer),
    label: d.optional(d.nullable(d.string)),
    database_id: d.optional(d.nullable(d.token)),
  }),
);

export const withdrawalReader = d.object({
  revision_id: d.optional(d.nullable(d.token)),
  catalog_revision: d.optional(catalogRevision),
  kind: d.optional(d.nullable(decisionKind)),
  decided_by: d.optional(decidedBy),
  decided_at: d.optional(d.nullable(d.timestamp)),
  // free-text: the reason the deciding person gave.
  reason: d.optional(d.nullable(d.string)),
  composition: compositionKey,
  /** After D3: the composition's newest approved runnable version, or null when none is left. */
  earlier_approved: d.optional(
    d.nullable(
      d.object({
        revision_id: d.token,
        catalog_revision: d.optional(catalogRevision),
      }),
    ),
  ),
});

export function withdrawnRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  craft: Pick<Member, "name" | "scid"> | null,
): QueueItem | null {
  const w = a.withdrawal;
  if (!w) return null;
  const name = compositionName(w.composition, w.catalog_revision);
  // ux on #632 (U25): a craft the console can't name is "Unknown spacecraft", never its id.
  const named = craft?.name?.trim() || null;
  const who = named ?? "Unknown spacecraft";
  const out = wayOut(name, w.earlier_approved);
  const to: RouteLocationRaw | null = craft
    ? { name: "ops.spacecraft", params: { scId: craft.scid, tab: "investigate" } }
    : null;
  return {
    ...base,
    key,
    title: `${who} · On ${name}, which is no longer approved.`,
    titleTo: to,
    sentence: [decisionLine(w), out].filter(Boolean).join(" "),
    meta: null,
    action: to
      ? { label: named ? `Open ${named}` : "Open spacecraft", to }
      : { label: "Open spacecraft", to: { name: "ops.fleet" } },
  };
}
