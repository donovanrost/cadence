import type { Snapshot } from "@cadence/plugin-sdk/admission";
import { oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
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
export type Context = Snapshot<{ organization_id: string; mission_id: string }>;
export type Page<T> = Snapshot<{ entries: T[]; page: number; page_size: 25; has_next: boolean }>;
export type Source = Snapshot<{
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
}>;
export type Binding = Snapshot<{
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
}>;
export type SourceEvent = Snapshot<{
  id: string;
  source_id: string;
  type: string;
  status: string;
  actor_id: string | null;
  occurred_at: string;
}>;
export type BindingEvent = Snapshot<
  SourceEvent & {
    binding_id: string;
    previous_source_id: string | null;
    version: number;
  }
>;
export type Observation = Snapshot<{
  id: string;
  source_id: string;
  binding_id: string | null;
  logical_source: string;
  realm: string | null;
  dataset: string | null;
  replay_run_id: string | null;
  observed_at: string;
  reason: string | null;
}>;
export type HealthEvent = Snapshot<Observation & { state: string }>;
export type Health = Snapshot<
  HealthEvent & { key: string; last_seen_at: string; transitions: number }
>;
export type Watermark = Snapshot<
  Observation & {
    key: string;
    complete_through: string | null;
    latest_receipt_time: string | null;
    retention_starts_at: string | null;
    confidence: string;
    sample_count: number;
    last_seen_at: string;
  }
>;
export type Job = Snapshot<{
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
}>;
export type Query = Snapshot<
  Record<PageKey, number> & {
    data_source_id: string | null;
    binding_id: string | null;
  }
>;
export type SourceModel = Snapshot<{
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
}>;
type RegistrationInput = {
  params: { source: Readonly<Registration> };
  review: Record<string, never>;
  confirmed: boolean;
};
export type SourceDecisionAction =
  | "disable-source"
  | "enable-source"
  | "reconcile-tsdb-backend"
  | "deprovision-tsdb-backend"
  | "provision-tsdb-backend"
  | "probe-source";
export type DeploymentAction = "retry-deployment-run" | "requeue-deployment-run";
type SourceDecision = {
  params: { "data-source-id": string };
  review: { source: string };
  confirmed: boolean;
};
export type SourceInputs = {
  "read-page": { query: Partial<Record<keyof Query, string | number | null>> };
  "validate-registration": RegistrationInput;
  "register-source": RegistrationInput;
  "change-binding": {
    params: { binding: { binding_id: string; data_source_id: string } };
    review: { source: string; binding: string; target_source: string };
    confirmed: boolean;
  };
  "rotate-source-credential": {
    params: { "data-source-id": string; "credentials-ref": string };
    review: { source: string };
    confirmed: boolean;
  };
} & Record<SourceDecisionAction, SourceDecision> &
  Record<
    DeploymentAction,
    { params: { "job-id": string }; review: { source: string; job: string }; confirmed: boolean }
  >;
export type SourceEffectAction = Exclude<SourceAction, "read-page" | "validate-registration">;
type ScopedSource = {
  dataSourceId: string;
  organizationId: string;
  missionId: string;
  status: string;
};
type JobResult = { jobId: string; runId: string; missionId: string; status: string };
type SourceEffectResult<A extends SourceEffectAction> = A extends "change-binding"
  ? ScopedSource & { bindingId: string; bindingVersion: number }
  : A extends DeploymentAction
    ? JobResult
    : A extends "rotate-source-credential"
      ? {
          reference: ScopedSource & { credentialsRef: string; credentialVersion: number };
          eventId: string;
        }
      : A extends "probe-source"
        ? {
            status: { health: string | null; reason: string | null; observedAt: string | null };
            event: "unchanged" | { dataSourceId: string; missionId: string; eventId: string };
          }
        : ScopedSource | { source: ScopedSource; job: JobResult };
export type SourceReceipt<A extends SourceEffectAction> = {
  readonly contract_version: 1;
  readonly organization_id: string;
  readonly mission_id: string;
  readonly actor_id: string;
  readonly operation_id: string;
  readonly action: A;
  readonly source_id: string;
  readonly event_ids: readonly string[];
  readonly result: Snapshot<SourceEffectResult<A>>;
};
type SourceResult<A extends SourceAction> = A extends "read-page"
  ? { readonly page_changed: true }
  : A extends "validate-registration"
    ? { readonly valid: boolean; readonly feedback: readonly string[] }
    : A extends SourceEffectAction
      ? SourceReceipt<A>
      : never;
export type SourceCommand<A extends SourceAction = SourceAction> = A extends SourceAction
  ? { readonly action: A; readonly input: Snapshot<SourceInputs[A]> }
  : never;
export type SourceOperation<A extends SourceAction = SourceAction> = A extends SourceAction
  ? SourceCommand<A> & {
      readonly id: string;
      readonly sequence: number;
      readonly feedback: readonly string[];
    } & (
        | { readonly status: "completed"; readonly result: SourceResult<A> }
        | { readonly status: "rejected"; readonly result: null }
        | {
            readonly status: "unconfirmed";
            readonly result: Readonly<{ source_id: string; operation_id: string }> | null;
          }
      )
  : never;
export function isSourceEffect(op: SourceOperation): op is SourceOperation<SourceEffectAction> {
  return op.action !== "read-page" && op.action !== "validate-registration";
}
export type SourcePage = Snapshot<{
  model: SourceModel;
  actor_id: string;
  sequence: number;
  operation: SourceOperation | null;
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
const keys = (v: Record<string, unknown>, expected: readonly string[]) =>
  Object.keys(v).length === expected.length && expected.every((k) => Object.hasOwn(v, k));
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
const page = <T extends { id: string }>(v: unknown, admit: Guard<T>): v is Page<T> =>
  object(v) &&
  sequence(v.page) &&
  v.page > 0 &&
  v.page_size === 25 &&
  typeof v.has_next === "boolean" &&
  arrayOf(v.entries, admit) &&
  v.entries.length <= 25 &&
  (!v.has_next || v.entries.length === 25) &&
  new Set(v.entries.map((x) => ("key" in x ? x.key : x.id))).size === v.entries.length;
const source = (v: unknown, context: Context): v is Source =>
  object(v) &&
  id(v.id) &&
  oneOf([null, context.organization_id], v.organization_id) &&
  oneOf([null, context.mission_id], v.mission_id) &&
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
  v.capabilities.every((c: unknown) => object(c) && id(c.name) && typeof c.enabled === "boolean") &&
  typeof v.capabilities_more === "boolean";
const binding = (v: unknown): v is Binding =>
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
const sourceEvent = (v: unknown): v is SourceEvent & Record<string, unknown> =>
  object(v) &&
  ["id", "source_id", "type", "status"].every((k) => id(v[k])) &&
  optional(v.actor_id, id) &&
  instant(v.occurred_at);
const bindingEvent = (v: unknown): v is BindingEvent =>
  sourceEvent(v) &&
  object(v) &&
  id(v.binding_id) &&
  optional(v.previous_source_id, id) &&
  count(v.version) &&
  v.version > 0;
const observation = (v: unknown): v is Observation & Record<string, unknown> =>
  object(v) &&
  id(v.id) &&
  id(v.source_id) &&
  id(v.logical_source) &&
  ["binding_id", "realm", "dataset", "replay_run_id", "reason"].every((k) =>
    optional(v[k], text),
  ) &&
  instant(v.observed_at);
const healthEvent = (v: unknown): v is HealthEvent & Record<string, unknown> =>
  observation(v) && object(v) && id(v.state);
const health = (v: unknown): v is Health =>
  healthEvent(v) && object(v) && id(v.key) && instant(v.last_seen_at) && count(v.transitions);
const watermark = (v: unknown): v is Watermark =>
  observation(v) &&
  object(v) &&
  id(v.key) &&
  ["complete_through", "latest_receipt_time", "retention_starts_at"].every((k) =>
    optional(v[k], instant),
  ) &&
  id(v.confidence) &&
  count(v.sample_count) &&
  instant(v.last_seen_at);
const job = (v: unknown): v is Job =>
  object(v) &&
  id(v.id) &&
  id(v.run_id) &&
  oneOf(["managed_questdb_provisioning", "tsdb_backend_lifecycle"], v.type) &&
  oneOf(["queued", "running", "completed", "failed"], v.status) &&
  count(v.attempts) &&
  optional(v.operation, text) &&
  optional(v.started_at, instant) &&
  optional(v.completed_at, instant) &&
  typeof v.failure_recorded === "boolean" &&
  hash(v.evidence);
const registration = (v: unknown): v is Registration =>
  object(v) &&
  keys(v, registrationFields) &&
  registrationFields.every((k) => text(v[k], k === "endpoint_ref" ? 2048 : 240));
const query = (v: unknown): v is Query =>
  object(v) &&
  keys(v, [...pageKeys, "data_source_id", "binding_id"]) &&
  pageKeys.every((k) => sequence(v[k]) && v[k] > 0) &&
  optional(v.data_source_id, id) &&
  optional(v.binding_id, id);
function validSourceModel(v: unknown, context: Context, mode: string): v is SourceModel {
  try {
    if (
      !object(v) ||
      v.contract_version !== 1 ||
      !same(v.context, context) ||
      v.mode !== mode ||
      !oneOf(["reader", "registration", "settings"], mode) ||
      !query(v.query) ||
      !object(v.permissions) ||
      typeof v.permissions.manage !== "boolean" ||
      (mode !== "reader" && !v.permissions.manage) ||
      !page(v.sources, (x): x is Source => source(x, context)) ||
      !page(v.bindings, binding) ||
      !registration(v.defaults) ||
      !Array.isArray(v.adapters) ||
      v.adapters.length > 100 ||
      !v.adapters.every(id) ||
      new Set(v.adapters).size !== v.adapters.length ||
      v.sources.page !== v.query.page ||
      v.bindings.page !== v.query.bindings_page
    )
      return false;
    const s = v.selected;
    if (s === null)
      return mode !== "settings" && v.query.data_source_id === null && v.query.binding_id === null;
    if (
      mode === "registration" ||
      !object(s) ||
      !source(s.source, context) ||
      s.source.id !== v.query.data_source_id ||
      !(s.binding === null
        ? v.query.binding_id === null
        : binding(s.binding) &&
          s.binding.id === v.query.binding_id &&
          s.binding.source_id === s.source.id)
    )
      return false;
    const selectedSource = s.source,
      selectedBinding = binding(s.binding) ? s.binding : null;
    if (!v.bindings.entries.every((b) => b.source_id === selectedSource.id)) return false;
    if (
      !page(s.events, sourceEvent) ||
      s.events.page !== v.query.events_page ||
      !s.events.entries.every((e) => e.source_id === selectedSource.id)
    )
      return false;
    if (
      !page(s.binding_events, bindingEvent) ||
      s.binding_events.page !== v.query.binding_events_page ||
      !s.binding_events.entries.every((e) => e.binding_id === selectedBinding?.id)
    )
      return false;
    if (
      !page(s.health, health) ||
      s.health.page !== v.query.health_page ||
      !s.health.entries.every((e) => e.source_id === selectedSource.id)
    )
      return false;
    if (
      !page(s.health_events, healthEvent) ||
      s.health_events.page !== v.query.health_events_page ||
      !s.health_events.entries.every((e) => e.source_id === selectedSource.id)
    )
      return false;
    if (
      !page(s.watermarks, watermark) ||
      s.watermarks.page !== v.query.watermarks_page ||
      !s.watermarks.entries.every((e) => e.source_id === selectedSource.id)
    )
      return false;
    if (!page(s.jobs, job) || s.jobs.page !== v.query.jobs_page) return false;
    return true;
  } catch {
    return false;
  }
}
export function admitSourceModel(v: unknown, context: Context, mode: string): SourceModel | null {
  return validSourceModel(v, context, mode) ? v : null;
}

export function validInput(v: unknown, action: SourceAction): boolean {
  if (!object(v)) return false;
  if (action === "read-page")
    return (
      keys(v, ["query"]) &&
      object(v.query) &&
      Object.entries(v.query).every(
        ([k, x]) =>
          oneOf([...pageKeys, "data_source_id", "binding_id"], k) &&
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
  const reviewKeys = oneOf(["register-source", "validate-registration"], action)
    ? []
    : action === "change-binding"
      ? ["source", "binding", "target_source"]
      : action.endsWith("deployment-run")
        ? ["source", "job"]
        : ["source"];
  if (!keys(v.review, reviewKeys) || !Object.values(v.review).every(hash)) return false;
  if (oneOf(["register-source", "validate-registration"], action))
    return (
      keys(v.params, ["source"]) &&
      registration(v.params.source) &&
      !!v.params.source.data_source_id.trim() &&
      !!v.params.source.logical_source.trim() &&
      oneOf(["managed_tsdb", "byo_tsdb"], v.params.source.kind) &&
      oneOf(
        ["shared", "org_isolated", "mission_isolated", "customer_owned"],
        v.params.source.isolation_level,
      ) &&
      oneOf(["questdb", "postgres_projection"], v.params.source.storage) &&
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
export function isSourceCommand(v: unknown): v is SourceCommand & Record<string, unknown> {
  return object(v) && oneOf(sourceActions, v.action) && validInput(v.input, v.action);
}
function receipt(
  v: unknown,
  op: SourceCommand<SourceEffectAction> & { id: string },
  p: Pick<SourcePage, "model" | "actor_id">,
): boolean {
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
  const scoped = (x: unknown, sourceId = v.source_id) =>
    object(x) &&
    x.dataSourceId === sourceId &&
    x.organizationId === v.organization_id &&
    x.missionId === v.mission_id &&
    id(x.status);
  const jobResult = (x: unknown) =>
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
      object(r.reference) &&
      r.reference.credentialsRef === op.input.params["credentials-ref"] &&
      count(r.reference.credentialVersion) &&
      id(r.eventId) &&
      oneOf(v.event_ids, r.eventId)
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
          oneOf(v.event_ids, r.event.eventId)))
    );
  if (object(r.job)) return scoped(r.source) && jobResult(r.job);
  return scoped(r);
}
function validSourceOperation(
  v: unknown,
  p: Pick<SourcePage, "model" | "actor_id">,
): v is SourceOperation {
  try {
    if (
      !isSourceCommand(v) ||
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
    if (v.status === "unconfirmed")
      return (
        v.result === null ||
        (object(v.result) &&
          keys(v.result, ["source_id", "operation_id"]) &&
          id(v.result.source_id) &&
          v.result.operation_id === v.id &&
          v.result.source_id ===
            (v.action === "register-source"
              ? v.input.params.source.data_source_id.trim()
              : p.model.selected?.source.id))
      );
    if (v.action === "read-page") return same(v.result, { page_changed: true });
    if (v.action === "validate-registration")
      return (
        object(v.result) &&
        typeof v.result.valid === "boolean" &&
        Array.isArray(v.result.feedback) &&
        v.result.feedback.length <= 20 &&
        v.result.feedback.every((x: unknown) => text(x))
      );
    return receipt(v.result, { ...v, id: v.id }, p);
  } catch {
    return false;
  }
}
export function admitSourceOperation(
  v: unknown,
  p: Pick<SourcePage, "model" | "actor_id">,
): SourceOperation | null {
  return validSourceOperation(v, p) ? v : null;
}
export function admitSourcePage(v: unknown, context: Context, mode: string): SourcePage | null {
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
