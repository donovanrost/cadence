import type {
  DecisionInput,
  DecisionResult,
  InboxData,
  InboxSnapshot,
  ReviewContext,
} from "./contracts";
type Check = (value: unknown) => boolean;
const record = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const text: Check = (v) => typeof v === "string" && v.length <= 4096;
const positive: Check = (v) => Number.isSafeInteger(v) && Number(v) > 0;
const shape =
  (fields: Record<string, Check>): Check =>
  (v) =>
    record(v) && Object.entries(fields).every(([key, check]) => check(v[key]));
const choice =
  (...values: unknown[]): Check =>
  (v) =>
    values.includes(v);
const nullable =
  (check: Check): Check =>
  (v) =>
    v === null || check(v);
const selected = shape({
  activation_request_id: text,
  binding_set_id: text,
  binding_set_version: positive,
});
const row = shape({
  __dom_id: text,
  activation_request_id: text,
  binding_set_id: text,
  binding_set_version: positive,
  status: shape({ label: text }),
  requester_display: text,
  review: shape({ id: text, label: text }),
});
const action = (decision: string) =>
  shape({ id: text, name: choice("decision"), value: choice(decision), label: text });
const dataShape = shape({
  page: shape({
    id: choice("activation-approval-inbox"),
    heading: text,
    subtitle: text,
    list: shape({ card_id: text, id: text, empty: shape({ id: text, copy: text }) }),
  }),
  selected: nullable(selected),
  form: shape({
    panel_id: text,
    id: text,
    request_id: shape({
      id: text,
      name: choice("activation_decision[request_id]"),
      type: choice("hidden"),
      value: text,
    }),
    reason: shape({
      id: text,
      name: choice("activation_decision[reason]"),
      type: choice("textarea"),
      value: text,
      label: text,
      required: choice(true),
    }),
    actions: shape({ approve: action("approved"), reject: action("rejected") }),
  }),
  activation_requests: (v) => Array.isArray(v) && v.length <= 100 && v.every(row),
});
export function assertInboxData(value: unknown): asserts value is InboxData {
  if (!dataShape(value)) throw new Error("Invalid activation inbox");
  const data = value as InboxData;
  const ids = data.activation_requests.map((row) => row.activation_request_id);
  if (
    new Set(ids).size !== ids.length ||
    (data.selected && !ids.includes(data.selected.activation_request_id))
  )
    throw new Error("Invalid activation selection");
}
export function admitInbox(value: unknown, scope: ReviewContext): InboxSnapshot | null {
  try {
    if (
      !shape({
        version: choice(1),
        status: choice("ready"),
        token: text,
        context: shape({ organization_id: text, mission_id: text }),
      })(value)
    )
      return null;
    const item = value as InboxSnapshot;
    if (
      !item.token ||
      item.context.organization_id !== scope.organization_id ||
      item.context.mission_id !== scope.mission_id
    )
      return null;
    assertInboxData(item.data);
    return item;
  } catch {
    return null;
  }
}
export function assertDecisionResult(
  value: unknown,
  input: DecisionInput,
): asserts value is DecisionResult {
  if (
    shape({ status: choice("unavailable") })(value) ||
    shape({ status: choice("invalid"), message: text })(value)
  )
    return;
  if (
    !shape({
      status: choice("ok"),
      data: shape({
        activationRequestId: choice(input.activation_decision.request_id),
        decision: choice(input.decision),
        outcome:
          input.decision === "rejected"
            ? choice("rejected")
            : choice("applied", "application_needs_review"),
      }),
    })(value)
  )
    throw new Error("Invalid activation decision result");
}
