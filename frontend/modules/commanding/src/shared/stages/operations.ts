import { digest, fail, id, record, stageState, text, time, visibility } from "./validation";
export type RequestReceipt = {
  request_id: string;
  item_id: string;
  state: string;
  requested_at: string;
};
export type Receipt = {
  operation: string;
  stage_id: string;
  actor_id: string;
  item_id?: string;
  updated_at?: string;
  name?: string;
  visibility?: "private" | "shared";
  state?: string;
  requests?: RequestReceipt[];
};
export type Rejection = { status: "rejected"; feedback: string };
export type Operation = { write_token: string; event: string } & (
  | { status: "unconfirmed" }
  | Rejection
  | { status: "completed"; receipt: Receipt }
);
const events: Record<string, string> = {
  create: "stage_created",
  edit_stage: "stage_updated",
  edit_details: "item_updated",
  cancel_item: "item_canceled",
  save_item: "item_created",
  submit: "requests_created",
};
export function readOperation(v: unknown, actor: string, stage: string): Operation {
  if (
    !record(v) ||
    !digest(v.write_token) ||
    typeof v.event !== "string" ||
    !Object.hasOwn(events, v.event)
  )
    return fail();
  if (v.status === "unconfirmed") return v as Operation;
  if (v.status === "rejected" && text(v.feedback)) return v as Operation;
  const r = v.receipt;
  if (
    v.status !== "completed" ||
    !record(r) ||
    r.actor_id !== actor ||
    r.stage_id !== stage ||
    !id(r.stage_id)
  )
    return fail();
  if (
    !(
      r.operation === events[v.event] ||
      (v.event === "save_item" && r.operation === "item_updated")
    )
  )
    return fail();
  if (["create", "edit_stage"].includes(v.event)) {
    if (
      !text(r.name, 240) ||
      !String(r.name).trim() ||
      !visibility(r.visibility) ||
      !stageState(r.state)
    )
      return fail();
  } else if (v.event === "submit") {
    if (!Array.isArray(r.requests) || r.requests.length < 1 || r.requests.length > 25)
      return fail();
    const requestIds = new Set(),
      itemIds = new Set();
    for (const q of r.requests) {
      if (
        !record(q) ||
        !id(q.request_id) ||
        !id(q.item_id) ||
        requestIds.has(q.request_id) ||
        itemIds.has(q.item_id) ||
        !time(q.requested_at) ||
        ![
          "draft",
          "validated",
          "approval_pending",
          "approved",
          "rejected",
          "queued",
          "released",
          "canceled",
        ].includes(String(q.state))
      )
        return fail();
      requestIds.add(q.request_id);
      itemIds.add(q.item_id);
    }
  } else if (!id(r.item_id) || !time(r.updated_at)) return fail();
  return v as Operation;
}
export function readWriteResult(
  v: unknown,
  actor: string,
  stage: string,
  token: string,
  event: string,
): Operation | Rejection {
  if (record(v) && v.status === "rejected" && text(v.feedback) && v.write_token === undefined)
    return { status: "rejected", feedback: v.feedback };
  const result = readOperation(v, actor, stage);
  if (result.write_token !== token || result.event !== event) return fail();
  return result;
}
