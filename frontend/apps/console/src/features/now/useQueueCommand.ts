import { shallowRef, type Ref } from "vue";
import { describeApiError, request } from "@/api/index.ts";
import { attentionReader, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/** What a row shows about its command: in flight, or the outcome until the row changes. */
export type CommandNote = Readonly<{
  running: boolean;
  /** The row's sentence when the command finished: "Retrying…" bridges until the read updates. */
  sentence: string;
  text: string | null;
}>;

export const NO_ACCESS = "Operators can retry storing.";

/** POST …/attention/contact_settlement/:id/retry (domain #71; operate_mission). */
export function retrySettlement(missionId: string, a: Attention) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(a.source)}/${encodeURIComponent(a.id)}/retry`,
    attentionReader,
    { method: "POST" },
  );
}

/**
 * U37 Retry storing / Retry all N (ux 294e67c6 + addendum; domain's final contract): one POST per
 * item. 200 and 409 retry_not_manual (someone already restarted it) count as retried; 404 means it
 * resolved meanwhile and drops out; 403 reads "Operators can retry storing."
 */
export async function retryTargets(
  missionId: string,
  targets: readonly Attention[],
): Promise<string | null> {
  let retried = 0;
  let dropped = 0;
  const failed: string[] = [];
  for (const a of targets) {
    const r = await retrySettlement(missionId, a);
    if (r.ok) retried += 1;
    else if (r.error.kind === "conflict" && r.error.code === "retry_not_manual") retried += 1;
    else if (r.error.kind === "not_found") dropped += 1;
    else if (r.error.kind === "forbidden") return NO_ACCESS;
    else failed.push(describeApiError(r.error));
  }
  const total = targets.length - dropped;
  if (targets.length === 1) return failed[0] ?? null;
  if (failed.length === 0) return `Retried ${retried}.`;
  const reason = failed[0]?.replace(/[.!?]+$/, "");
  return `Retried ${retried} of ${total}. ${failed.length} failed${reason ? `: ${reason}` : ""}.`;
}

export function useQueueCommand(missionId: Ref<string>, onDone: () => void) {
  const notes = shallowRef<Readonly<Record<string, CommandNote>>>({});
  const set = (key: string, note: CommandNote) => (notes.value = { ...notes.value, [key]: note });

  async function run(item: QueueItem) {
    if (!item.command || notes.value[item.key]?.running) return;
    set(item.key, { running: true, sentence: item.sentence, text: null });
    const text = await retryTargets(missionId.value, item.command.targets);
    set(item.key, { running: false, sentence: item.sentence, text });
    onDone();
  }

  /** The row's sentence: "Retrying…" until the read moves on, then the outcome after it. */
  function sentenceFor(item: QueueItem, canRun: boolean): string {
    const note = notes.value[item.key];
    const base = item.command && !canRun ? `${item.sentence} ${NO_ACCESS}` : item.sentence;
    if (!note) return base;
    if (note.running || (note.text === null && note.sentence === item.sentence)) return "Retrying…";
    return note.text ? `${base} ${note.text}` : base;
  }

  return { notes, run, sentenceFor };
}
