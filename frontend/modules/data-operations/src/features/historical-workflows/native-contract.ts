import type { Snapshot } from "@cadence/plugin-sdk/admission";
import { oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
export const historyActions = [
  "read-page",
  "validate-request",
  "record-request",
  "transition-group",
  "retry-group",
  "request-correction",
] as const;
export type HistoryAction = (typeof historyActions)[number];
export const requestFields = [
  "workflow",
  "run_id",
  "realm",
  "data_source_id",
  "source_binding_id",
  "point_ids",
  "source_from",
  "source_to",
  "reason",
  "confirmed",
] as const;
export type RequestValues = Record<(typeof requestFields)[number], string>;
export type HistoryContext = Snapshot<{ organization_id: string; mission_id: string }>;
export type Page<T> = Snapshot<{ entries: T[]; page: number; page_size: 25; total: number }>;
export type Summary = Snapshot<{ state: string; progress: string; [key: string]: number | string }>;
export type Group = Snapshot<{
  id: string;
  event_count: number;
  last_event_at: string;
  workflow: string;
  summary: Summary | null;
}>;
export type Binding = Snapshot<{
  id: string;
  source_id: string;
  realm: string;
  version: number;
  evidence: string;
}>;
export type AuditEvent = Snapshot<{
  id: string;
  run_id: string;
  event_type: string;
  stage: string;
  point_id: string | null;
  realm: string;
  source_id: string;
  binding_id: string;
  source_from: string | null;
  source_to: string | null;
  occurred_at: string;
  actor_id: string | null;
  reason: string;
  reason_truncated: boolean;
  operation_id: string | null;
  correction_available: boolean;
}>;
export type Job = Snapshot<{
  id: string;
  run_id: string;
  status: string;
  attempts: number;
  started_at: string | null;
  completed_at: string | null;
}>;
export type Query = Snapshot<{
  group: string | null;
  binding_q: string;
  page: number;
  audit_page: number;
  jobs_page: number;
  origins_page: number;
  bindings_page: number;
}>;
export type HistoryModel = Snapshot<{
  contract_version: 1;
  context: HistoryContext;
  mode: "reader" | "manage";
  query: Query;
  permissions: { request: boolean; manage: boolean };
  groups: Page<Group>;
  bindings: Page<Binding>;
  defaults: RequestValues;
  selected: null | {
    id: string;
    workflow: string;
    evidence: string;
    summary: Summary;
    audit: Page<AuditEvent>;
    jobs: Page<Job>;
    origins: Page<{ kind: "dashboard" | "comparison_review"; id: string }>;
    transitions: { stage: HistoryStage; eligible_count: number; blocked_count: number }[];
    retry: { eligible_count: number };
  };
}>;
export const historyStages = ["approved", "rejected", "started", "completed", "failed"] as const;
export type HistoryStage = (typeof historyStages)[number];
type GroupDecision = { group_id: string; evidence: string; reason: string; confirmed: true };
type RequestInput = { request: Readonly<RequestValues>; binding_evidence: string };
export type HistoryInputs = {
  "read-page": { query: Partial<Record<keyof Query, string>> };
  "validate-request": RequestInput;
  "record-request": RequestInput;
  "transition-group": GroupDecision & { stage: HistoryStage };
  "retry-group": GroupDecision;
  "request-correction": GroupDecision & { event_id: string };
};
export type HistoryEffectAction = Exclude<HistoryAction, "read-page" | "validate-request">;
export type HistoryReceipt<A extends HistoryEffectAction = HistoryEffectAction> = {
  readonly contract_version: 1;
  readonly organization_id: string;
  readonly mission_id: string;
  readonly actor_id: string;
  readonly operation_id: string;
  readonly action: A;
  readonly group_id: string;
  readonly event_ids: readonly string[];
  readonly event_count: number;
  readonly event_ids_truncated: boolean;
  readonly event_digest: string;
  readonly job_ids: readonly string[];
  readonly job_count: number;
  readonly job_ids_truncated: boolean;
} & (A extends "retry-group"
  ? {
      readonly retry_counts: Readonly<{
        retried: number;
        skipped: number;
        nonretryable: number;
        failed: number;
      }>;
    }
  : {});
type HistoryResult<A extends HistoryAction> = A extends "read-page"
  ? { readonly page_changed: true }
  : A extends "validate-request"
    ? {
        readonly valid: boolean;
        readonly feedback: readonly { readonly field: string; readonly code: string }[];
      }
    : A extends HistoryEffectAction
      ? HistoryReceipt<A>
      : never;
export type HistoryCommand<A extends HistoryAction = HistoryAction> = A extends HistoryAction
  ? { readonly action: A; readonly input: Snapshot<HistoryInputs[A]> }
  : never;
export type HistoryOperation<A extends HistoryAction = HistoryAction> = A extends HistoryAction
  ? HistoryCommand<A> & {
      readonly id: string;
      readonly sequence: number;
      readonly feedback: readonly string[];
    } & (
        | { readonly status: "completed"; readonly result: HistoryResult<A> }
        | { readonly status: "rejected"; readonly result: null }
        | {
            readonly status: "unconfirmed";
            readonly result: Readonly<{ group_id: string; operation_id: string }> | null;
          }
      )
  : never;
export function isHistoryEffect(op: HistoryOperation): op is HistoryOperation<HistoryEffectAction> {
  return op.action !== "read-page" && op.action !== "validate-request";
}
export type HistoryPage = Snapshot<{
  model: HistoryModel;
  actor_id: string;
  sequence: number;
  operation: HistoryOperation | null;
  read_error: boolean;
}>;
const object = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => text(v) && !!v;
const count = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const sequence = (v: unknown): v is number => count(v) && v <= 1000000;
const hash = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const instant = (v: unknown): v is string =>
  text(v) && /(?:Z|[+-]\d\d:\d\d)$/.test(v) && Number.isFinite(Date.parse(v));
const optional = <T>(v: unknown, admit: Guard<T>): v is T | null => v === null || admit(v);
const stages = historyStages;
const keys = (v: Record<string, unknown>, expected: readonly string[]) =>
  Object.keys(v).length === expected.length && expected.every((k) => Object.hasOwn(v, k));
const summary = (v: unknown): v is Summary =>
  object(v) &&
  text(v.state) &&
  text(v.progress) &&
  Object.entries(v).every(([k, x]) => (oneOf(["state", "progress"], k) ? text(x) : count(x)));
const page = <T extends { id: string }>(v: unknown, admit: Guard<T>): v is Page<T> =>
  object(v) &&
  sequence(v.page) &&
  v.page > 0 &&
  v.page_size === 25 &&
  count(v.total) &&
  arrayOf(v.entries, admit) &&
  v.entries.length <= 25 &&
  new Set(v.entries.map((x) => ("kind" in x ? String(x.kind) + ":" + x.id : x.id))).size ===
    v.entries.length;
const group = (v: unknown): v is Group =>
  object(v) &&
  id(v.id) &&
  count(v.event_count) &&
  instant(v.last_event_at) &&
  oneOf(["backfill", "import", "mixed", "unavailable"], v.workflow) &&
  optional(v.summary, summary);
const binding = (v: unknown): v is Binding =>
  object(v) &&
  id(v.id) &&
  id(v.source_id) &&
  id(v.realm) &&
  count(v.version) &&
  v.version > 0 &&
  hash(v.evidence);
const audit = (v: unknown): v is AuditEvent =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
  text(v.event_type) &&
  text(v.stage) &&
  /^(backfill|import)_(requested|approved|rejected|started|completed|failed|retried)$/.test(
    v.event_type,
  ) &&
  v.event_type.endsWith("_" + v.stage) &&
  optional(v.point_id, id) &&
  text(v.realm) &&
  id(v.source_id) &&
  id(v.binding_id) &&
  optional(v.source_from, instant) &&
  optional(v.source_to, instant) &&
  instant(v.occurred_at) &&
  optional(v.actor_id, id) &&
  text(v.reason, 4096) &&
  typeof v.reason_truncated === "boolean" &&
  optional(v.operation_id, id) &&
  typeof v.correction_available === "boolean";
const job = (v: unknown): v is Job =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
  oneOf(["queued", "running", "completed", "failed"], v.status) &&
  count(v.attempts) &&
  optional(v.started_at, instant) &&
  optional(v.completed_at, instant);
const origin = (v: unknown): v is { kind: "dashboard" | "comparison_review"; id: string } =>
  object(v) && oneOf(["dashboard", "comparison_review"], v.kind) && id(v.id);
function query(v: unknown): v is Query {
  return (
    object(v) &&
    keys(v, [
      "group",
      "binding_q",
      "page",
      "audit_page",
      "jobs_page",
      "origins_page",
      "bindings_page",
    ]) &&
    optional(v.group, id) &&
    text(v.binding_q, 200) &&
    ["page", "audit_page", "jobs_page", "origins_page", "bindings_page"].every(
      (k) => sequence(v[k]) && v[k] > 0,
    )
  );
}
const request = (v: unknown): v is RequestValues =>
  object(v) && keys(v, requestFields) && Object.values(v).every((x) => text(x, 8192));
function validHistoryModel(v: unknown, context: HistoryContext, mode: string): v is HistoryModel {
  try {
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !object(v.context) ||
      v.context.organization_id !== context.organization_id ||
      v.context.mission_id !== context.mission_id ||
      v.mode !== mode ||
      !oneOf(["reader", "manage"], mode) ||
      !query(v.query) ||
      !object(v.permissions) ||
      typeof v.permissions.request !== "boolean" ||
      typeof v.permissions.manage !== "boolean" ||
      !page(v.groups, group) ||
      !page(v.bindings, binding) ||
      !request(v.defaults)
    )
      return false;
    const s = v.selected;
    if (
      s !== null &&
      (!object(s) ||
        s.id !== v.query.group ||
        !id(s.id) ||
        !oneOf(["backfill", "import", "mixed"], s.workflow) ||
        !hash(s.evidence) ||
        !summary(s.summary) ||
        !page(s.audit, audit) ||
        !page(s.jobs, job) ||
        !page(s.origins, origin) ||
        !Array.isArray(s.transitions) ||
        s.transitions.length !== 5 ||
        new Set(s.transitions.map((x: unknown) => (object(x) ? x.stage : undefined))).size !== 5 ||
        !s.transitions.every(
          (x: unknown) =>
            object(x) &&
            oneOf(stages, x.stage) &&
            count(x.eligible_count) &&
            count(x.blocked_count),
        ) ||
        !object(s.retry) ||
        !count(s.retry.eligible_count))
    )
      return false;
    if (s === null && v.query.group !== null) return false;
    return true;
  } catch {
    return false;
  }
}
export function admitHistoryModel(
  v: unknown,
  context: HistoryContext,
  mode: string,
): HistoryModel | null {
  return validHistoryModel(v, context, mode) ? v : null;
}

export function same(a: unknown, b: unknown): boolean {
  return (
    a === b ||
    (object(a) &&
      object(b) &&
      Object.keys(a).length === Object.keys(b).length &&
      Object.keys(a).every((k) => Object.hasOwn(b, k) && same(a[k], b[k]))) ||
    (Array.isArray(a) &&
      Array.isArray(b) &&
      a.length === b.length &&
      a.every((x, i) => same(x, b[i])))
  );
}
function validInput(v: unknown, action: HistoryAction): boolean {
  if (!object(v)) return false;
  if (action === "read-page")
    return (
      keys(v, ["query"]) &&
      object(v.query) &&
      Object.entries(v.query).every(
        ([k, x]) =>
          oneOf(
            [
              "group",
              "binding_q",
              "page",
              "audit_page",
              "jobs_page",
              "origins_page",
              "bindings_page",
            ],
            k,
          ) && text(x),
      )
    );
  if (oneOf(["validate-request", "record-request"], action))
    return (
      keys(v, ["request", "binding_evidence"]) && request(v.request) && text(v.binding_evidence, 64)
    );
  const expected = [
    "group_id",
    "evidence",
    "reason",
    "confirmed",
    ...(action === "transition-group"
      ? ["stage"]
      : action === "request-correction"
        ? ["event_id"]
        : []),
  ];
  return (
    keys(v, expected) &&
    id(v.group_id) &&
    hash(v.evidence) &&
    text(v.reason, 4096) &&
    !!v.reason.trim() &&
    v.confirmed === true &&
    (action !== "transition-group" || oneOf(stages, v.stage)) &&
    (action !== "request-correction" || id(v.event_id))
  );
}
export function isHistoryCommand(
  value: unknown,
): value is HistoryCommand & Record<string, unknown> {
  return (
    object(value) && oneOf(historyActions, value.action) && validInput(value.input, value.action)
  );
}
function receipt(
  v: unknown,
  op: { readonly id: string; readonly action: HistoryAction },
  p: Pick<HistoryPage, "model" | "actor_id">,
): boolean {
  const ids = (values: unknown, total: unknown, truncated: unknown) =>
    Array.isArray(values) &&
    values.length <= 25 &&
    values.every(id) &&
    new Set(values).size === values.length &&
    count(total) &&
    values.length === Math.min(total, 25) &&
    truncated === total > 25;
  return (
    object(v) &&
    v.contract_version === 1 &&
    v.organization_id === p.model.context.organization_id &&
    v.mission_id === p.model.context.mission_id &&
    v.actor_id === p.actor_id &&
    v.operation_id === op.id &&
    v.action === op.action &&
    id(v.group_id) &&
    ids(v.event_ids, v.event_count, v.event_ids_truncated) &&
    ids(v.job_ids, v.job_count, v.job_ids_truncated) &&
    hash(v.event_digest) &&
    (op.action !== "retry-group" ||
      (object(v.retry_counts) &&
        keys(v.retry_counts, ["retried", "skipped", "nonretryable", "failed"]) &&
        Object.values(v.retry_counts).every(count) &&
        v.retry_counts.retried === v.event_count))
  );
}
export function admitHistoryOperation(
  v: unknown,
  p: Pick<HistoryPage, "model" | "actor_id">,
): HistoryOperation | null {
  return validHistoryOperation(v, p) ? v : null;
}
function validHistoryOperation(
  v: unknown,
  p: Pick<HistoryPage, "model" | "actor_id">,
): v is HistoryOperation {
  try {
    if (
      !isHistoryCommand(v) ||
      !id(v.id) ||
      !sequence(v.sequence) ||
      !v.sequence ||
      !oneOf(["completed", "rejected", "unconfirmed"], v.status) ||
      !Array.isArray(v.feedback) ||
      v.feedback.length > 10 ||
      !v.feedback.every((x: unknown) => text(x))
    )
      return false;
    if (v.status === "rejected") return v.result === null;
    if (
      v.status === "unconfirmed" &&
      (v.result === null ||
        (object(v.result) &&
          keys(v.result, ["group_id", "operation_id"]) &&
          id(v.result.group_id) &&
          v.result.operation_id === v.id))
    )
      return true;
    if (v.status !== "completed") return false;
    if (v.action === "read-page") return same(v.result, { page_changed: true });
    if (v.action === "validate-request")
      return (
        object(v.result) &&
        typeof v.result.valid === "boolean" &&
        Array.isArray(v.result.feedback) &&
        v.result.feedback.length <= 20 &&
        v.result.feedback.every((x: unknown) => object(x) && text(x.field) && text(x.code))
      );
    return receipt(v.result, { id: v.id, action: v.action }, p);
  } catch {
    return false;
  }
}
export function admitHistoryPage(
  v: unknown,
  context: HistoryContext,
  mode: string,
): HistoryPage | null {
  try {
    const model = object(v) && admitHistoryModel(v.model, context, mode);
    if (!model || !id(v.actor_id) || !sequence(v.sequence) || typeof v.read_error !== "boolean")
      return null;
    const operation =
      v.operation === null
        ? null
        : admitHistoryOperation(v.operation, { model, actor_id: v.actor_id });
    if (v.operation !== null && (!operation || operation.sequence !== v.sequence)) return null;
    return {
      model,
      actor_id: v.actor_id,
      sequence: v.sequence,
      operation,
      read_error: v.read_error,
    };
  } catch {
    return null;
  }
}
