import { shallowRef, type Ref } from "vue";
import { decoders as d, decode, describeApiError, request } from "@/api/index.ts";
import { attentionReader, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

export const NO_ACCESS = "Operators can retry storing.";

/** POST …/attention/contact_settlement/:id/retry (domain #71; operate_mission). */
export function retrySettlement(missionId: string, a: Attention) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(a.source)}/${encodeURIComponent(a.id)}/retry`,
    attentionReader,
    { method: "POST" },
  );
}

export type RetryOutcome = Readonly<{
  /** The row's note: an error sentence, or the folded result; null when there's nothing to say. */
  text: string | null;
  /** Items as the server returned them (200, or 409's details.item): the row takes them now. */
  items: readonly Attention[];
  /** A fold where every item was retried: it empties, so hold it 5 s reading `text` (ux). */
  emptied: boolean;
}>;

const conflictItem = d.object({ item: attentionReader });

/**
 * U37 Retry storing / Retry all N (ux 294e67c6 + addendum; domain's final contract): one POST per
 * item. 200 and 409 retry_not_manual (someone already restarted it) count as retried and carry the
 * item; 404 means it resolved meanwhile and drops out; 403 reads "Operators can retry storing."
 */
export async function retryTargets(
  missionId: string,
  targets: readonly Attention[],
): Promise<RetryOutcome> {
  let dropped = 0;
  const items: Attention[] = [];
  const failed: string[] = [];
  for (const a of targets) {
    const r = await retrySettlement(missionId, a);
    if (r.ok) {
      items.push(r.value);
      continue;
    }
    const e = r.error;
    if (e.kind === "conflict" && e.code === "retry_not_manual") {
      const current = decode(conflictItem, e.details);
      if (current.ok) items.push(current.value.item);
    } else if (e.kind === "not_found") dropped += 1;
    else if (e.kind === "forbidden") return { text: NO_ACCESS, items, emptied: false };
    else failed.push(describeApiError(e));
  }
  const retried = targets.length - dropped - failed.length;
  if (targets.length === 1) return { text: failed[0] ?? null, items, emptied: false };
  if (failed.length === 0) return { text: `Retried ${retried}.`, items, emptied: retried > 0 };
  const reason = failed[0]?.replace(/[.!?]+$/, "");
  return {
    text: `Retried ${retried} of ${targets.length - dropped}. ${failed.length} failed${reason ? `: ${reason}` : ""}.`,
    items,
    emptied: false,
  };
}

/** Row commands for the queue panel: "Retrying…" only while the requests run (ux). */
export function useQueueCommand(
  missionId: Ref<string>,
  onDone: (row: QueueItem, outcome: RetryOutcome) => void,
) {
  const running = shallowRef<ReadonlySet<string>>(new Set());
  const notes = shallowRef<Readonly<Record<string, string>>>({});

  async function run(item: QueueItem) {
    if (!item.command || running.value.has(item.key)) return;
    running.value = new Set([...running.value, item.key]);
    try {
      const outcome = await retryTargets(missionId.value, item.command.targets);
      const { [item.key]: _old, ...rest } = notes.value;
      notes.value = outcome.text && !outcome.emptied ? { ...rest, [item.key]: outcome.text } : rest;
      onDone(item, outcome);
    } finally {
      running.value = new Set([...running.value].filter((k) => k !== item.key));
    }
  }

  function sentenceFor(item: QueueItem, canRun: boolean): string {
    if (running.value.has(item.key)) return "Retrying…";
    const base = item.command && !canRun ? `${item.sentence} ${NO_ACCESS}` : item.sentence;
    const note = notes.value[item.key];
    return note ? `${base} ${note}` : base;
  }

  return { running, run, sentenceFor };
}
