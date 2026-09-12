export const sourceActions = [
  "read-page",
  "validate-registration",
  "register-source",
  "change-binding",
  "disable-source",
  "enable-source",
  "reconcile-tsdb-backend",
  "deprovision-tsdb-backend",
  "provision-tsdb-backend",
  "probe-source",
  "rotate-source-credential",
  "retry-deployment-run",
  "requeue-deployment-run",
] as const;
export type SourceAction = (typeof sourceActions)[number];
export const registrationFields = [
  "data_source_id",
  "logical_source",
  "kind",
  "isolation_level",
  "credentials_ref",
  "credential_provider",
  "endpoint_ref",
  "material_env_profile",
  "http_endpoint_env",
  "storage",
] as const;
export const pageKeys = [
  "page",
  "bindings_page",
  "events_page",
  "binding_events_page",
  "health_page",
  "health_events_page",
  "watermarks_page",
  "jobs_page",
] as const;
export type PageKey = (typeof pageKeys)[number];
export type Registration = Record<(typeof registrationFields)[number], string>;
export type Context = { organization_id: string; mission_id: string };
export type Page<T> = { entries: T[]; page: number; page_size: 25; has_next: boolean };
export type Source = {
  id: string;
  organization_id: string | null;
  mission_id: string | null;
  owner: string;
  kind: string;
  status: string;
  isolation: string;
  logical_source: string | null;
  credential_reference: string | null;
  event_id: string | null;
  editable: boolean;
  evidence: string;
  backend: { status: string | null; operation: string | null };
  capabilities: { name: string; enabled: boolean }[];
  capabilities_more: boolean;
};
export type Binding = {
  id: string;
  source_id: string;
  logical_source: string;
  realm: string;
  dataset: string | null;
  priority: number;
  status: string;
  version: number;
  event_id: string | null;
  active_from: string | null;
  active_to: string | null;
  editable: boolean;
  evidence: string;
};
export type SourceEvent = {
  id: string;
  source_id: string;
  type: string;
  status: string;
  actor_id: string | null;
  occurred_at: string;
};
export type BindingEvent = SourceEvent & {
  binding_id: string;
  previous_source_id: string | null;
  version: number;
};
export type Observation = {
  id: string;
  source_id: string;
  binding_id: string | null;
  logical_source: string;
  realm: string | null;
  dataset: string | null;
  replay_run_id: string | null;
  observed_at: string;
  reason: string | null;
};
export type HealthEvent = Observation & { state: string };
export type Health = HealthEvent & { key: string; last_seen_at: string; transitions: number };
export type Watermark = Observation & {
  key: string;
  complete_through: string | null;
  latest_receipt_time: string | null;
  retention_starts_at: string | null;
  confidence: string;
  sample_count: number;
  last_seen_at: string;
};
export type Job = {
  id: string;
  run_id: string;
  type: string;
  status: string;
  attempts: number;
  operation: string | null;
  started_at: string | null;
  completed_at: string | null;
  failure_recorded: boolean;
  evidence: string;
};
export type Query = Record<PageKey, number> & {
  data_source_id: string | null;
  binding_id: string | null;
};
export type SourceModel = {
  contract_version: 1;
  context: Context;
  mode: "reader" | "registration" | "settings";
  query: Query;
  permissions: { manage: boolean };
  sources: Page<Source>;
  bindings: Page<Binding>;
  selected: null | {
    source: Source;
    binding: Binding | null;
    events: Page<SourceEvent>;
    binding_events: Page<BindingEvent>;
    health: Page<Health>;
    health_events: Page<HealthEvent>;
    watermarks: Page<Watermark>;
    jobs: Page<Job>;
  };
  adapters: string[];
  defaults: Registration;
};
export type SourceOperation = {
  id: string;
  sequence: number;
  action: SourceAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  result: Record<string, any> | null;
  feedback: string[];
};
export type SourcePage = {
  model: SourceModel;
  actor_id: string;
  sequence: number;
  operation: SourceOperation | null;
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
const keys = (v: Record<string, any>, expected: readonly string[]) =>
  Object.keys(v).length === expected.length && expected.every((k) => Object.hasOwn(v, k));
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
const page = (v: any, admit: (v: any) => boolean): boolean =>
  object(v) &&
  sequence(v.page) &&
  v.page > 0 &&
  v.page_size === 25 &&
  typeof v.has_next === "boolean" &&
  Array.isArray(v.entries) &&
  v.entries.length <= 25 &&
  (!v.has_next || v.entries.length === 25) &&
  v.entries.every(admit) &&
  new Set(v.entries.map((x: any) => x.key ?? x.id)).size === v.entries.length;
const source = (v: any, context: Context): boolean =>
  object(v) &&
  id(v.id) &&
  [null, context.organization_id].includes(v.organization_id) &&
  [null, context.mission_id].includes(v.mission_id) &&
  ["owner", "kind", "status", "isolation"].every((k) => id(v[k])) &&
  ["logical_source", "credential_reference", "event_id"].every((k) => optional(v[k], id)) &&
  v.editable ===
    (v.organization_id === context.organization_id && v.mission_id === context.mission_id) &&
  hash(v.evidence) &&
  object(v.backend) &&
  optional(v.backend.status, text) &&
  optional(v.backend.operation, text) &&
  Array.isArray(v.capabilities) &&
  v.capabilities.length <= 25 &&
  v.capabilities.every((c: any) => object(c) && id(c.name) && typeof c.enabled === "boolean") &&
  typeof v.capabilities_more === "boolean";
const binding = (v: any): boolean =>
  object(v) &&
  ["id", "source_id", "logical_source", "realm", "status"].every((k) => id(v[k])) &&
  optional(v.dataset, text) &&
  Number.isSafeInteger(v.priority) &&
  count(v.version) &&
  v.version > 0 &&
  optional(v.event_id, id) &&
  optional(v.active_from, instant) &&
  optional(v.active_to, instant) &&
  typeof v.editable === "boolean" &&
  hash(v.evidence);
const sourceEvent = (v: any): boolean =>
  object(v) &&
  ["id", "source_id", "type", "status"].every((k) => id(v[k])) &&
  optional(v.actor_id, id) &&
  instant(v.occurred_at);
const bindingEvent = (v: any): boolean =>
  sourceEvent(v) &&
  id(v.binding_id) &&
  optional(v.previous_source_id, id) &&
  count(v.version) &&
  v.version > 0;
const observation = (v: any): boolean =>
  object(v) &&
  id(v.id) &&
  id(v.source_id) &&
  id(v.logical_source) &&
  ["binding_id", "realm", "dataset", "replay_run_id", "reason"].every((k) =>
    optional(v[k], text),
  ) &&
  instant(v.observed_at);
const healthEvent = (v: any): boolean => observation(v) && id(v.state);
const health = (v: any): boolean =>
  healthEvent(v) && id(v.key) && instant(v.last_seen_at) && count(v.transitions);
const watermark = (v: any): boolean =>
  observation(v) &&
  id(v.key) &&
  ["complete_through", "latest_receipt_time", "retention_starts_at"].every((k) =>
    optional(v[k], instant),
  ) &&
  id(v.confidence) &&
  count(v.sample_count) &&
  instant(v.last_seen_at);
const job = (v: any): boolean =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
  ["managed_questdb_provisioning", "tsdb_backend_lifecycle"].includes(v.type) &&
  ["queued", "running", "completed", "failed"].includes(v.status) &&
  count(v.attempts) &&
  optional(v.operation, text) &&
  optional(v.started_at, instant) &&
  optional(v.completed_at, instant) &&
  typeof v.failure_recorded === "boolean" &&
  hash(v.evidence);
const registration = (v: any): boolean =>
  object(v) &&
  keys(v, registrationFields) &&
  registrationFields.every((k) => text(v[k], k === "endpoint_ref" ? 2048 : 240));
const query = (v: any): boolean =>
  object(v) &&
  keys(v, [...pageKeys, "data_source_id", "binding_id"]) &&
  pageKeys.every((k) => sequence(v[k]) && v[k] > 0) &&
  optional(v.data_source_id, id) &&
  optional(v.binding_id, id);
export function admitSourceModel(v: any, context: Context, mode: string): SourceModel | null {
  try {
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !same(v.context, context) ||
      v.mode !== mode ||
      !["reader", "registration", "settings"].includes(mode) ||
      !query(v.query) ||
      !object(v.permissions) ||
      typeof v.permissions.manage !== "boolean" ||
      (mode !== "reader" && !v.permissions.manage) ||
      !page(v.sources, (x) => source(x, context)) ||
      !page(v.bindings, binding) ||
      !registration(v.defaults) ||
      !Array.isArray(v.adapters) ||
      v.adapters.length > 100 ||
      !v.adapters.every(id) ||
      new Set(v.adapters).size !== v.adapters.length ||
      v.sources.page !== v.query.page ||
      v.bindings.page !== v.query.bindings_page
    )
      return null;
    const s = v.selected;
    if (s === null)
      return mode !== "settings" && v.query.data_source_id === null && v.query.binding_id === null
        ? (v as SourceModel)
        : null;
    if (
      mode === "registration" ||
      !object(s) ||
      !source(s.source, context) ||
      s.source.id !== v.query.data_source_id ||
      !v.bindings.entries.every((b: Binding) => b.source_id === s.source.id) ||
      !(s.binding === null
        ? v.query.binding_id === null
        : binding(s.binding) &&
          s.binding.id === v.query.binding_id &&
          s.binding.source_id === s.source.id)
    )
      return null;
    const collections: [string, PageKey, (x: any) => boolean][] = [
      ["events", "events_page", sourceEvent],
      ["binding_events", "binding_events_page", bindingEvent],
      ["health", "health_page", health],
      ["health_events", "health_events_page", healthEvent],
      ["watermarks", "watermarks_page", watermark],
      ["jobs", "jobs_page", job],
    ];
    for (const [key, selector, admit] of collections) {
      if (!page(s[key], admit) || s[key].page !== v.query[selector]) return null;
      if (key === "binding_events") {
        if (!s[key].entries.every((e: BindingEvent) => e.binding_id === s.binding?.id)) return null;
      } else if (
        key !== "jobs" &&
        !s[key].entries.every((e: SourceEvent) => e.source_id === s.source.id)
      )
        return null;
    }
    return v as SourceModel;
  } catch {
    return null;
  }
}
export function validInput(v: any, action: SourceAction): boolean {
  if (!object(v)) return false;
  if (action === "read-page")
    return (
      keys(v, ["query"]) &&
      object(v.query) &&
      Object.entries(v.query).every(
        ([k, x]) =>
          [...pageKeys, "data_source_id", "binding_id"].includes(k) &&
          (x === null || text(x) || sequence(x)),
      )
    );
  if (
    !keys(v, ["params", "review", "confirmed"]) ||
    !object(v.params) ||
    !object(v.review) ||
    typeof v.confirmed !== "boolean"
  )
    return false;
  const reviewKeys = ["register-source", "validate-registration"].includes(action)
    ? []
    : action === "change-binding"
      ? ["source", "binding", "target_source"]
      : action.endsWith("deployment-run")
        ? ["source", "job"]
        : ["source"];
  if (!keys(v.review, reviewKeys) || !Object.values(v.review).every(hash)) return false;
  if (["register-source", "validate-registration"].includes(action))
    return (
      keys(v.params, ["source"]) &&
      registration(v.params.source) &&
      !!v.params.source.data_source_id.trim() &&
      !!v.params.source.logical_source.trim() &&
      ["managed_tsdb", "byo_tsdb"].includes(v.params.source.kind) &&
      ["shared", "org_isolated", "mission_isolated", "customer_owned"].includes(
        v.params.source.isolation_level,
      ) &&
      ["questdb", "postgres_projection"].includes(v.params.source.storage) &&
      (v.params.source.kind === "byo_tsdb"
        ? !!v.params.source.credentials_ref.trim() && v.params.source.isolation_level !== "shared"
        : v.params.source.isolation_level !== "customer_owned")
    );
  if (action === "change-binding")
    return (
      keys(v.params, ["binding"]) &&
      object(v.params.binding) &&
      keys(v.params.binding, ["binding_id", "data_source_id"]) &&
      Object.values(v.params.binding).every(id)
    );
  const expected = action.endsWith("deployment-run")
    ? ["job-id"]
    : action === "rotate-source-credential"
      ? ["data-source-id", "credentials-ref"]
      : ["data-source-id"];
  return keys(v.params, expected) && Object.values(v.params).every(id);
}
function receipt(v: any, op: SourceOperation, p: Pick<SourcePage, "model" | "actor_id">): boolean {
  if (
    !object(v) ||
    v.contract_version !== 1 ||
    v.organization_id !== p.model.context.organization_id ||
    v.mission_id !== p.model.context.mission_id ||
    v.actor_id !== p.actor_id ||
    v.operation_id !== op.id ||
    v.action !== op.action ||
    !id(v.source_id) ||
    !object(v.result) ||
    !Array.isArray(v.event_ids) ||
    v.event_ids.length > 25 ||
    !v.event_ids.every(id) ||
    new Set(v.event_ids).size !== v.event_ids.length
  )
    return false;
  const expectedSource =
    op.action === "register-source"
      ? op.input.params.source.data_source_id.trim()
      : p.model.selected?.source.id;
  if (v.source_id !== expectedSource) return false;
  const scoped = (x: any, sourceId = v.source_id) =>
    object(x) &&
    x.dataSourceId === sourceId &&
    x.organizationId === v.organization_id &&
    x.missionId === v.mission_id &&
    id(x.status);
  const jobResult = (x: any) =>
    object(x) && id(x.jobId) && id(x.runId) && x.missionId === v.mission_id && id(x.status);
  const r = v.result;
  if (op.action === "change-binding")
    return (
      scoped(r, op.input.params.binding.data_source_id) &&
      r.bindingId === op.input.params.binding.binding_id &&
      count(r.bindingVersion)
    );
  if (op.action.endsWith("deployment-run")) return jobResult(r);
  if (op.action === "rotate-source-credential")
    return (
      scoped(r.reference) &&
      r.reference.credentialsRef === op.input.params["credentials-ref"] &&
      count(r.reference.credentialVersion) &&
      id(r.eventId) &&
      v.event_ids.includes(r.eventId)
    );
  if (op.action === "probe-source")
    return (
      object(r.status) &&
      optional(r.status.health, text) &&
      optional(r.status.reason, text) &&
      optional(r.status.observedAt, instant) &&
      (r.event === "unchanged" ||
        (object(r.event) &&
          r.event.dataSourceId === v.source_id &&
          r.event.missionId === v.mission_id &&
          id(r.event.eventId) &&
          v.event_ids.includes(r.event.eventId)))
    );
  if (object(r.job)) return scoped(r.source) && jobResult(r.job);
  return scoped(r);
}
export function admitSourceOperation(
  v: any,
  p: Pick<SourcePage, "model" | "actor_id">,
): SourceOperation | null {
  try {
    if (
      !object(v) ||
      !id(v.id) ||
      !sequence(v.sequence) ||
      !v.sequence ||
      !sourceActions.includes(v.action) ||
      !validInput(v.input, v.action) ||
      !["completed", "rejected", "unconfirmed"].includes(v.status) ||
      !Array.isArray(v.feedback) ||
      v.feedback.length > 10 ||
      !v.feedback.every((x: any) => text(x))
    )
      return null;
    if (v.status === "rejected") return v.result === null ? (v as SourceOperation) : null;
    if (v.status === "unconfirmed")
      return v.result === null ||
        (object(v.result) &&
          keys(v.result, ["source_id", "operation_id"]) &&
          id(v.result.source_id) &&
          v.result.operation_id === v.id &&
          v.result.source_id ===
            (v.action === "register-source"
              ? v.input.params.source.data_source_id.trim()
              : p.model.selected?.source.id))
        ? (v as SourceOperation)
        : null;
    if (v.action === "read-page")
      return same(v.result, { page_changed: true }) ? (v as SourceOperation) : null;
    if (v.action === "validate-registration")
      return object(v.result) &&
        typeof v.result.valid === "boolean" &&
        Array.isArray(v.result.feedback) &&
        v.result.feedback.length <= 20 &&
        v.result.feedback.every((x: any) => text(x))
        ? (v as SourceOperation)
        : null;
    return receipt(v.result, v as SourceOperation, p) ? (v as SourceOperation) : null;
  } catch {
    return null;
  }
}
export function admitSourcePage(v: any, context: Context, mode: string): SourcePage | null {
  try {
    const model = object(v) && admitSourceModel(v.model, context, mode);
    if (!model || !id(v.actor_id) || !sequence(v.sequence) || typeof v.read_error !== "boolean")
      return null;
    const operation =
      v.operation === null
        ? null
        : admitSourceOperation(v.operation, { model, actor_id: v.actor_id });
    if (v.operation !== null && (!operation || operation.sequence !== v.sequence)) return null;
    if (v.operation === null && v.sequence !== 0) return null;
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
