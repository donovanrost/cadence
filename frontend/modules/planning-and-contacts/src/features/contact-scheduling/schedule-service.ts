import { record, oneOf, type Snapshot } from "@cadence/plugin-sdk/admission";
import type {
  ContactSchedule,
  ScheduleContext,
  ScheduleInputs,
  ScheduleReceipt,
  ScheduleRoute,
  ScheduleSearchResult,
} from "./OpsContactSchedule.contracts";
import { admitContactSchedule, admitReceipt, admitSearch, sameEvidence } from "./contact-schedule";

export type ScheduleCommand = {
  [A in "reserve" | "cancel"]: Snapshot<{
    operationId: string;
    action: A;
    input: ScheduleInputs[A];
  }>;
}["reserve" | "cancel"];
export type ScheduleRejection = Readonly<{
  status: "not_accepted";
  operation_id: string;
  reason: "conflict" | "review_changed";
}>;
export type ScheduleSubmission = ScheduleOperation | ScheduleRejection;
export type ScheduleOperationRef = Readonly<{ operationId: string; action: "reserve" | "cancel" }>;
type OperationIdentity = Snapshot<{
  contract_version: 2;
  operation_id: string;
  actor_id: string;
  context: ScheduleContext;
  action: "reserve" | "cancel";
  reservation_id: string;
  revision: number;
}>;
export type ScheduleOperation = OperationIdentity &
  (
    | { readonly status: "accepted" | "rejected"; readonly result: null }
    | { readonly status: "unconfirmed"; readonly result: ScheduleReceipt | null }
    | { readonly status: "completed"; readonly result: ScheduleReceipt }
  );
export type ScheduleProjection = Snapshot<{
  model: ContactSchedule;
  actorId: string;
  operations: { page: number; more: boolean; entries: ScheduleOperation[] };
}>;

/** Features see domain operations; only adapters see unknown wire data. */
export interface ContactScheduleService {
  readonly context: ScheduleContext;
  admit(value: unknown): ScheduleProjection;
  read(): Promise<ScheduleProjection>;
  search(input: ScheduleInputs["search"], route: ScheduleRoute): Promise<ScheduleSearchResult>;
  submit(command: ScheduleCommand): Promise<ScheduleSubmission>;
  observe(operation: ScheduleOperationRef): Promise<ScheduleOperation | null>;
}
export type ScheduleWireRequest =
  | ["search", { contract_version: 2; payload: ScheduleInputs["search"] }]
  | {
      [A in "reserve" | "cancel"]: [
        A,
        { contract_version: 2; operation_id: string; payload: ScheduleInputs[A] },
      ];
    }["reserve" | "cancel"]
  | ["reserve" | "cancel", { contract_version: 2; operation_id: string; observe: true }];
export interface ScheduleTransport {
  read(): Promise<unknown>;
  execute(...request: ScheduleWireRequest): Promise<unknown>;
}
const identifier = (value: unknown): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  new TextEncoder().encode(value).length <= 240 &&
  !/\s/.test(value) &&
  value
    .split("")
    .every((character) => character.charCodeAt(0) > 31 && character.charCodeAt(0) !== 127);
const uuid = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value);
function copy(value: unknown): unknown {
  const encoded = JSON.stringify(value);
  if (!encoded || new TextEncoder().encode(encoded).length > 262144)
    throw Error("Unavailable scheduling evidence");
  return JSON.parse(encoded);
}

export function readScheduleOperation(
  raw: unknown,
  context: ScheduleContext,
  actorId: string,
): ScheduleOperation {
  const value = copy(raw);
  if (
    !record(value) ||
    value.contract_version !== 2 ||
    !uuid(value.operation_id) ||
    value.actor_id !== actorId ||
    !record(value.context) ||
    !sameEvidence(value.context, context) ||
    !oneOf(["reserve", "cancel"], value.action) ||
    !identifier(value.reservation_id) ||
    typeof value.revision !== "number" ||
    !Number.isSafeInteger(value.revision) ||
    value.revision < 1
  )
    throw Error("Unverified scheduling operation");
  const identity: OperationIdentity = {
    contract_version: 2,
    operation_id: value.operation_id,
    actor_id: actorId,
    context,
    action: value.action,
    reservation_id: value.reservation_id,
    revision: value.revision,
  };
  if (oneOf(["accepted", "rejected"], value.status) && value.result === null)
    return { ...identity, status: value.status, result: null };
  const result = admitReceipt(value.result, value.reservation_id);
  if (value.status === "unconfirmed" && (value.result === null || result))
    return { ...identity, status: "unconfirmed", result };
  if (
    value.status === "completed" &&
    result &&
    (value.action === "cancel"
      ? result.lifecycleState === "canceled"
      : oneOf(
          ["pending", "confirmed", "active", "completed", "rejected", "canceled"],
          result.lifecycleState,
        ))
  )
    return { ...identity, status: "completed", result };
  throw Error("Unverified scheduling outcome");
}

export function createContactScheduleService(
  transport: ScheduleTransport,
  captured: ScheduleContext,
  expectedActor?: string,
): ContactScheduleService {
  const context = Object.freeze({ ...captured });
  let actor = expectedActor;
  let pinnedQuery: ContactSchedule["query"] | undefined;
  function admit(raw: unknown): ScheduleProjection {
    const value = copy(raw);
    const model = admitContactSchedule(value, context);
    if (
      !model ||
      !record(value) ||
      !record(value.workflow) ||
      value.workflow.contract_version !== 2 ||
      !identifier(value.workflow.actor_id) ||
      (actor !== undefined && actor !== value.workflow.actor_id) ||
      !record(value.workflow.operations)
    )
      throw Error("Unsupported scheduling projection");
    const page = value.workflow.operations;
    if (
      page.page !== model.query.operations_page ||
      typeof page.more !== "boolean" ||
      !Array.isArray(page.entries) ||
      page.entries.length > 10 ||
      (page.more && page.entries.length !== 10)
    )
      throw Error("Unverified scheduling history");
    if (pinnedQuery && !sameEvidence(pinnedQuery, model.query))
      throw Error("Different scheduling query");
    const actorId = value.workflow.actor_id;
    const entries = page.entries.map((item: unknown) =>
      readScheduleOperation(item, context, actorId),
    );
    if (new Set(entries.map((op) => op.operation_id)).size !== entries.length)
      throw Error("Repeated scheduling operation");
    actor = actorId;
    pinnedQuery = model.query;
    return {
      model,
      actorId,
      operations: { page: model.query.operations_page, more: page.more, entries },
    };
  }
  function operation(value: unknown, ref: ScheduleOperationRef) {
    if (!actor) throw Error("Scheduling identity unavailable");
    const op = readScheduleOperation(value, context, actor);
    if (op.operation_id !== ref.operationId || op.action !== ref.action)
      throw Error("Different scheduling operation");
    return op;
  }
  return {
    context,
    admit,
    async read() {
      return admit(await transport.read());
    },
    async search(input, route) {
      const review = structuredClone({ input, route });
      const result = await transport.execute("search", {
        contract_version: 2,
        payload: review.input,
      });
      const found = admitSearch(result, context, review.input.contact_search, review.route);
      if (!found) throw Error("Unverified provider opportunities");
      return found;
    },
    async submit(command) {
      if (!actor || !uuid(command.operationId)) throw Error("Scheduling identity unavailable");
      const raw =
        command.action === "reserve"
          ? await transport.execute("reserve", {
              contract_version: 2,
              operation_id: command.operationId,
              payload: command.input,
            })
          : await transport.execute("cancel", {
              contract_version: 2,
              operation_id: command.operationId,
              payload: command.input,
            });
      if (
        record(raw) &&
        raw.contract_version === 2 &&
        raw.status === "not_accepted" &&
        raw.operation_id === command.operationId &&
        oneOf(["conflict", "review_changed"], raw.reason)
      )
        return { status: "not_accepted", operation_id: command.operationId, reason: raw.reason };
      const op = operation(raw, command);
      if (
        command.action === "cancel" &&
        op.reservation_id !== command.input.reservation_evidence.reservation_id
      )
        throw Error("Different cancellation target");
      return op;
    },
    async observe(ref) {
      const raw = await transport.execute(ref.action, {
        contract_version: 2,
        operation_id: ref.operationId,
        observe: true,
      });
      if (!record(raw) || !("operation" in raw)) throw Error("Unverified operation observation");
      return raw.operation === null ? null : operation(raw.operation, ref);
    },
  };
}
