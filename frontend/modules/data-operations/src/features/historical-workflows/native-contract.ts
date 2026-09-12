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
export type HistoryContext = { organization_id: string; mission_id: string };
export type Page<T> = { entries: T[]; page: number; page_size: 25; total: number };
export type Summary = { state: string; progress: string; [key: string]: number | string };
export type Group = {
  id: string;
  event_count: number;
  last_event_at: string;
  workflow: string;
  summary: Summary | null;
};
export type Binding = {
  id: string;
  source_id: string;
  realm: string;
  version: number;
  evidence: string;
};
export type AuditEvent = {
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
};
export type Job = {
  id: string;
  run_id: string;
  status: string;
  attempts: number;
  started_at: string | null;
  completed_at: string | null;
};
export type Query = {
  group: string | null;
  binding_q: string;
  page: number;
  audit_page: number;
  jobs_page: number;
  origins_page: number;
  bindings_page: number;
};
export type HistoryModel = {
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
    transitions: { stage: string; eligible_count: number; blocked_count: number }[];
    retry: { eligible_count: number };
  };
};
export type HistoryOperation = {
  id: string;
  sequence: number;
  action: HistoryAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  result: Record<string, any> | null;
  feedback: string[];
};
export type HistoryPage = {
  model: HistoryModel;
  actor_id: string;
  sequence: number;
  operation: HistoryOperation | null;
  read_error: boolean;
};
const object = (v: any): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => text(v) && !!v;
const count = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const sequence = (v: unknown): v is number => count(v) && v <= 1000000;
const hash = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const instant = (v: unknown): v is string =>
  text(v) && /(?:Z|[+-]\d\d:\d\d)$/.test(v) && Number.isFinite(Date.parse(v));
const optional = (v: unknown, admit: (v: any) => boolean) => v === null || admit(v);
const stages = ["approved", "rejected", "started", "completed", "failed"];
const keys = (v: Record<string, any>, expected: readonly string[]) =>
  Object.keys(v).length === expected.length && expected.every((k) => Object.hasOwn(v, k));
const summary = (v: any): v is Summary =>
  object(v) &&
  text(v.state) &&
  text(v.progress) &&
  Object.entries(v).every(([k, x]) => (["state", "progress"].includes(k) ? text(x) : count(x)));
const page = <T>(v: any, admit: (v: any) => v is T): v is Page<T> =>
  object(v) &&
  sequence(v.page) &&
  v.page > 0 &&
  v.page_size === 25 &&
  count(v.total) &&
  Array.isArray(v.entries) &&
  v.entries.length <= 25 &&
  v.entries.every(admit) &&
  new Set(v.entries.map((x: any) => (x.kind ? x.kind + ":" + x.id : x.id))).size ===
    v.entries.length;
const group = (v: any): v is Group =>
  object(v) &&
  id(v.id) &&
  count(v.event_count) &&
  instant(v.last_event_at) &&
  ["backfill", "import", "mixed", "unavailable"].includes(v.workflow) &&
  optional(v.summary, summary);
const binding = (v: any): v is Binding =>
  object(v) &&
  id(v.id) &&
  id(v.source_id) &&
  id(v.realm) &&
  count(v.version) &&
  v.version > 0 &&
  hash(v.evidence);
const audit = (v: any): v is AuditEvent =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
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
const job = (v: any): v is Job =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
  ["queued", "running", "completed", "failed"].includes(v.status) &&
  count(v.attempts) &&
  optional(v.started_at, instant) &&
  optional(v.completed_at, instant);
const origin = (v: any): v is { kind: "dashboard" | "comparison_review"; id: string } =>
  object(v) && ["dashboard", "comparison_review"].includes(v.kind) && id(v.id);
function query(v: any): v is Query {
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
const request = (v: any): v is RequestValues =>
  object(v) && keys(v, requestFields) && Object.values(v).every((x) => text(x, 8192));
export function admitHistoryModel(
  v: any,
  context: HistoryContext,
  mode: string,
): HistoryModel | null {
  try {
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !object(v.context) ||
      v.context.organization_id !== context.organization_id ||
      v.context.mission_id !== context.mission_id ||
      v.mode !== mode ||
      !query(v.query) ||
      !object(v.permissions) ||
      typeof v.permissions.request !== "boolean" ||
      typeof v.permissions.manage !== "boolean" ||
      !page(v.groups, group) ||
      !page(v.bindings, binding) ||
      !request(v.defaults)
    )
      return null;
    const s = v.selected;
    if (
      s !== null &&
      (!object(s) ||
        s.id !== v.query.group ||
        !id(s.id) ||
        !["backfill", "import", "mixed"].includes(s.workflow) ||
        !hash(s.evidence) ||
        !summary(s.summary) ||
        !page(s.audit, audit) ||
        !page(s.jobs, job) ||
        !page(s.origins, origin) ||
        !Array.isArray(s.transitions) ||
        s.transitions.length !== 5 ||
        new Set(s.transitions.map((x: any) => x.stage)).size !== 5 ||
        !s.transitions.every(
          (x: any) =>
            object(x) &&
            stages.includes(x.stage) &&
            count(x.eligible_count) &&
            count(x.blocked_count),
        ) ||
        !object(s.retry) ||
        !count(s.retry.eligible_count))
    )
      return null;
    if (s === null && v.query.group !== null) return null;
    return v as HistoryModel;
  } catch {
    return null;
  }
}
export function same(a: any, b: any): boolean {
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
function validInput(v: any, action: HistoryAction): boolean {
  if (!object(v)) return false;
  if (action === "read-page")
    return (
      keys(v, ["query"]) &&
      object(v.query) &&
      Object.entries(v.query).every(
        ([k, x]) =>
          [
            "group",
            "binding_q",
            "page",
            "audit_page",
            "jobs_page",
            "origins_page",
            "bindings_page",
          ].includes(k) && text(x),
      )
    );
  if (["validate-request", "record-request"].includes(action))
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
    (action !== "transition-group" || stages.includes(v.stage)) &&
    (action !== "request-correction" || id(v.event_id))
  );
}
function receipt(
  v: any,
  op: HistoryOperation,
  p: Pick<HistoryPage, "model" | "actor_id">,
): boolean {
  const ids = (values: any, total: any, truncated: any) =>
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
  v: any,
  p: Pick<HistoryPage, "model" | "actor_id">,
): HistoryOperation | null {
  try {
    if (
      !object(v) ||
      !id(v.id) ||
      !sequence(v.sequence) ||
      !v.sequence ||
      !historyActions.includes(v.action) ||
      !validInput(v.input, v.action) ||
      !["completed", "rejected", "unconfirmed"].includes(v.status) ||
      !Array.isArray(v.feedback) ||
      v.feedback.length > 10 ||
      !v.feedback.every((x: any) => text(x))
    )
      return null;
    if (v.status === "rejected") return v.result === null ? (v as HistoryOperation) : null;
    if (
      v.status === "unconfirmed" &&
      (v.result === null ||
        (object(v.result) &&
          keys(v.result, ["group_id", "operation_id"]) &&
          id(v.result.group_id) &&
          v.result.operation_id === v.id))
    )
      return v as HistoryOperation;
    if (v.action === "read-page")
      return same(v.result, { page_changed: true }) ? (v as HistoryOperation) : null;
    if (v.action === "validate-request")
      return object(v.result) &&
        typeof v.result.valid === "boolean" &&
        Array.isArray(v.result.feedback) &&
        v.result.feedback.length <= 20 &&
        v.result.feedback.every((x: any) => object(x) && text(x.field) && text(x.code))
        ? (v as HistoryOperation)
        : null;
    return receipt(v.result, v as HistoryOperation, p) ? (v as HistoryOperation) : null;
  } catch {
    return null;
  }
}
export function admitHistoryPage(
  v: any,
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
