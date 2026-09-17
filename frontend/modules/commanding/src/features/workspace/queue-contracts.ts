import { readPreview, type Preview } from "../../shared/command-draft/contracts";
import { bounded, digest, fail, id, record, time } from "../../shared/stages/validation";

export type QueuePreview = Readonly<{
  token: string;
  actor_id: string;
  requests: readonly Preview[];
}>;
export type EnqueueReceipt = Readonly<{
  request_id: string;
  target_id: string;
  requested_at: string;
}> &
  ({ state: "queued"; queue_id: string } | { state: "approval_pending"; queue_id: null });

export function readQueuePreview(value: unknown, actor: string): QueuePreview {
  bounded(value, 524_288);
  if (
    !digest(value.token) ||
    value.actor_id !== actor ||
    !Array.isArray(value.requests) ||
    value.requests.length < 1 ||
    value.requests.length > 25
  )
    return fail();
  const requests = value.requests.map((request: unknown) =>
    readPreview(request, { actor_id: actor }),
  );
  if (
    new Set(requests.map((request) => request.request_id)).size !== requests.length ||
    new Set(requests.map((request) => request.target.id)).size !== requests.length ||
    new Set(requests.map((request) => request.command_id)).size !== 1
  )
    return fail();
  return { token: value.token, actor_id: actor, requests };
}

export function readEnqueueReceipt(value: unknown, actor: string): readonly EnqueueReceipt[] {
  if (
    !record(value) ||
    value.operation !== "commands_submitted" ||
    value.actor_id !== actor ||
    !Array.isArray(value.requests) ||
    value.requests.length < 1 ||
    value.requests.length > 25
  )
    return fail();
  const requests = value.requests.map((raw: unknown): EnqueueReceipt => {
    if (!record(raw) || !id(raw.request_id) || !id(raw.target_id) || !time(raw.requested_at))
      return fail();
    const base = {
      request_id: raw.request_id,
      target_id: raw.target_id,
      requested_at: raw.requested_at,
    };
    if (raw.state === "queued" && id(raw.queue_id))
      return { ...base, state: raw.state, queue_id: raw.queue_id };
    if (raw.state === "approval_pending" && raw.queue_id === null)
      return { ...base, state: raw.state, queue_id: null };
    return fail();
  });
  const queues = requests.flatMap((request) => (request.queue_id ? [request.queue_id] : []));
  if (
    new Set(requests.map((request) => request.request_id)).size !== requests.length ||
    new Set(requests.map((request) => request.target_id)).size !== requests.length ||
    new Set(queues).size !== queues.length
  )
    return fail();
  return requests;
}
