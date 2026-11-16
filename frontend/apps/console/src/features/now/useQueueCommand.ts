import type { MissionId } from "@/api/index.ts";
import { shallowRef, type Ref } from "vue";
import {
  decoders as d,
  describeApiError,
  detailsOf,
  isError,
  request,
  type ApiResult,
} from "@/api/index.ts";
import { NO_ACCESS_ARCHIVE } from "./archive.ts";
import { NO_ACCESS_JOB } from "./jobs.ts";
import { attentionReader, serverKey, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

export const NO_ACCESS = "Operators can retry storing.";
/** ux bda6f91d: lost telemetry closes with Mark as seen (acknowledge, operate_mission). */
export const NO_ACCESS_SEEN = "Operators mark lost telemetry as seen.";

/** ux U45: a missed pass (contact_start) closes the same way. */
export const NO_ACCESS_MISSED = "Operators mark missed passes as seen.";

/** ux U47: lost frames (ingress_backpressure) are acknowledged, not marked seen. */
export const NO_ACCESS_ACK_LOST = "Operators acknowledge lost telemetry.";

export type CommandKind = "retry" | "seen" | "book";
/** U61: a 403 from POST …/execute (the server's own rule, operate_mission today). */
export const NO_ACCESS_BOOK = "You can't start booking for this plan.";
const seenNoAccess = (a: Attention | undefined) =>
  a?.source === "contact_start"
    ? NO_ACCESS_MISSED
    : a?.source === "ingress_backpressure"
      ? NO_ACCESS_ACK_LOST
      : NO_ACCESS_SEEN;
export const noAccessText = (kind: CommandKind, targets: readonly Attention[]) =>
  kind === "book"
    ? NO_ACCESS_BOOK
    : kind === "seen"
      ? seenNoAccess(targets[0])
      : targets[0]?.source === "archive_quarantine"
        ? NO_ACCESS_ARCHIVE
        : NO_ACCESS;

/** POST …/acknowledge on a lost settlement (backlog.lost) or a missed pass (U45). */
export function markSeen(missionId: MissionId, a: Attention) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}/acknowledge`,
    attentionReader,
    { method: "POST" },
  );
}

/** Mark as seen: the returned item (resolved) shows at once; 404 = already closed, silently. */
export async function seenTargets(
  missionId: MissionId,
  targets: readonly Attention[],
): Promise<RetryOutcome> {
  const items: Attention[] = [];
  for (const a of targets) {
    const r = await markSeen(missionId, a);
    if (r.ok) items.push(r.value);
    else if (r.error.kind === "forbidden") return { text: seenNoAccess(a), items, emptied: false };
    else if (r.error.kind !== "not_found")
      return { text: describeApiError(r.error), items, emptied: false };
  }
  return { text: null, items, emptied: false };
}

/**
 * U61 Start / Continue booking: POST …/contact-plans/:id/execute (idempotent; the server refuses
 * with 403 whoever it wouldn't let book). The item leaves Now on the next read once booking runs.
 */
export async function bookTargets(
  missionId: MissionId,
  targets: readonly Attention[],
): Promise<RetryOutcome> {
  const planId = targets[0]?.plan?.id;
  if (!planId) return { text: null, items: [], emptied: false };
  const r = await request(
    `/missions/${encodeURIComponent(missionId)}/contact-plans/${encodeURIComponent(planId)}/execute`,
    d.object({ plan_id: d.token }),
    { method: "POST", body: {} },
  );
  if (r.ok) return { text: "Booking started.", items: [], emptied: false };
  if (r.error.kind === "forbidden") return { text: NO_ACCESS_BOOK, items: [], emptied: false };
  return { text: describeApiError(r.error), items: [], emptied: false };
}

/** archive_quarantine's retry answers with counts beside the item (api, U49). */
const archiveRetry = d.object({
  item: attentionReader,
  indexed: d.integer,
  still_failing: d.integer,
});

/**
 * POST …/attention/:source/:id/retry (operate_mission): contact_settlement (#71) answers with the
 * item; archive_quarantine (#88) with {item, indexed, still_failing}, read here down to the item.
 */
export async function retrySettlement(
  missionId: MissionId,
  a: Attention,
): Promise<ApiResult<Attention>> {
  const path = `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}/retry`;
  if (a.source !== "archive_quarantine") return request(path, attentionReader, { method: "POST" });
  const r = await request(path, archiveRetry, { method: "POST" });
  return r.ok ? { ok: true, value: r.value.item } : r;
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
  missionId: MissionId,
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
    if (isError(e, "retry_not_manual")) {
      const current = detailsOf(e, conflictItem);
      if (current) items.push(current.item);
    } else if (e.kind === "not_found") dropped += 1;
    else if (e.kind === "forbidden")
      return { text: noAccessText("retry", [a]), items, emptied: false };
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
  missionId: Ref<MissionId>,
  onDone: (row: QueueItem, outcome: RetryOutcome) => void,
) {
  const running = shallowRef<ReadonlySet<string>>(new Set());
  const notes = shallowRef<Readonly<Record<string, string>>>({});

  async function run(item: QueueItem) {
    if (!item.command || running.value.has(item.key)) return;
    running.value = new Set([...running.value, item.key]);
    try {
      const { kind, targets } = item.command;
      const act = kind === "seen" ? seenTargets : kind === "book" ? bookTargets : retryTargets;
      const outcome = await act(missionId.value, targets);
      const { [item.key]: _old, ...rest } = notes.value;
      notes.value = outcome.text && !outcome.emptied ? { ...rest, [item.key]: outcome.text } : rest;
      onDone(item, outcome);
    } finally {
      running.value = new Set([...running.value].filter((k) => k !== item.key));
    }
  }

  function sentenceFor(item: QueueItem, canRun: boolean): string {
    if (running.value.has(item.key))
      return item.command?.kind === "book"
        ? "Starting booking…"
        : item.command?.kind !== "seen"
          ? "Retrying…"
          : item.command.targets[0]?.source === "ingress_backpressure"
            ? "Acknowledging…"
            : "Marking…";
    const base =
      item.command && !canRun
        ? `${item.sentence} ${noAccessText(item.command.kind, item.command.targets)}`
        : item.job && !canRun
          ? `${item.sentence} ${NO_ACCESS_JOB}`
          : item.sentence;
    const note = notes.value[item.key];
    return note ? `${base} ${note}` : base;
  }

  return { running, run, sentenceFor };
}
