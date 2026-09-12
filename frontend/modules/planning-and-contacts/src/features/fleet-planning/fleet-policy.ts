import { admitPolicyEvidence, type PolicyEvidence } from "./policy-evidence";
export const policyActions = [
  "validate-policy",
  "save-policy",
  "approve-policy",
  "validate-grant",
  "issue-grant",
  "revoke-grant",
] as const;
export type PolicyAction = (typeof policyActions)[number];
export const policyValidation = (action: PolicyAction) =>
  action === "validate-policy" || action === "validate-grant";
export type PolicyContext = { organization_id: string; mission_id: string };
export type PolicyValues = {
  max_horizon_seconds: number;
  requirement_concurrency: number;
  provider_search_concurrency: number;
  reuse_freshness_seconds: number;
  max_contacts: number | null;
  max_estimated_cost_micros: number | null;
  currency: string | null;
  critical_contact_reserve: number;
  automation_mode: "advisory" | "approval_required" | "bounded_automatic";
  execution_concurrency: number;
  max_repair_attempts: number;
  repair_horizon_seconds: number;
  automatic_submission: boolean;
  distinct_provider_required: boolean;
  distinct_station_required: boolean;
  distinct_service_pool_required: boolean;
  default_exclusive_capacity: number;
};
export type PolicyVersion = { reference: PolicyEvidence; values: PolicyValues };
export type GrantEvidence = PolicyContext & {
  contract_version: 1;
  grant_id: string;
  content_sha256: string;
};
export type PolicyGrant = {
  reference: GrantEvidence;
  service_identity_id: string;
  policy_id: string;
  policy_version: number;
  state: "active" | "revoked";
  actions: string[];
  maximum_horizon_seconds: number;
  maximum_contacts: number;
  maximum_execution_concurrency: number;
  maximum_estimated_cost_micros: number | null;
  currency: string | null;
  valid_from: string;
  valid_until: string;
  approved_at: string;
  approval_reason: string;
  revoked_at: string | null;
  revocation_reason: string;
};
export type PolicyModel = {
  contract_version: 1;
  context: PolicyContext;
  query: { grants_page: number; identities_page: number };
  state: "unconfigured" | "draft" | "active" | "retired";
  current: PolicyVersion | null;
  active: PolicyVersion | null;
  defaults: PolicyValues;
  permissions: { edit: boolean; approve: boolean; grants: boolean };
  grants: { page: number; more: boolean; active_count: number; entries: PolicyGrant[] };
  identities: { page: number; more: boolean; entries: { id: string; name: string }[] };
};
export type PolicyOperation = {
  sequence: number;
  action: PolicyAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  receipt: { receiptId: string; completedAt: string; result: Record<string, any> } | null;
};
export type PolicyPage = {
  model: PolicyModel;
  sequence: number;
  operation: PolicyOperation | null;
};
export const equalPolicyData = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a, ordered) === JSON.stringify(b, ordered);
const ordered = (_: string, v: any) =>
  record(v)
    ? Object.fromEntries(
        Object.keys(v)
          .sort()
          .map((k) => [k, v[k]]),
      )
    : v;
const record = (v: any): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: any, max = 240) =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  Array.from(v).every((character) => {
    const code = character.codePointAt(0)!;
    return (
      (code >= 32 || [9, 10, 13].includes(code)) &&
      code !== 127 &&
      !(code >= 0xd800 && code <= 0xdfff)
    );
  });
const id = (v: any) => text(v) && v.length > 0 && !/\s/.test(v);
const hash = (v: any) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const nat = (v: any) => Number.isSafeInteger(v) && v >= 0;
const pos = (v: any) => nat(v) && v > 0;
const time = (v: any) =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const nullable = (v: any, check: (v: any) => boolean) => v === null || check(v);
const sameContext = (v: any, c: PolicyContext) =>
  record(v) && v.organization_id === c.organization_id && v.mission_id === c.mission_id;
const cost = (v: any) =>
  nullable(v.max_estimated_cost_micros, nat) &&
  nullable(v.currency, (c: any) => /^[A-Z]{3}$/.test(c)) &&
  (v.max_estimated_cost_micros === null || v.currency !== null);
function values(v: any): boolean {
  return (
    record(v) &&
    [
      "max_horizon_seconds",
      "requirement_concurrency",
      "provider_search_concurrency",
      "execution_concurrency",
      "repair_horizon_seconds",
      "default_exclusive_capacity",
    ].every((k) => pos(v[k])) &&
    ["reuse_freshness_seconds", "critical_contact_reserve", "max_repair_attempts"].every((k) =>
      nat(v[k]),
    ) &&
    nullable(v.max_contacts, pos) &&
    cost(v) &&
    [
      "automatic_submission",
      "distinct_provider_required",
      "distinct_station_required",
      "distinct_service_pool_required",
    ].every((k) => typeof v[k] === "boolean") &&
    ["advisory", "approval_required", "bounded_automatic"].includes(v.automation_mode)
  );
}
const version = (v: any, c: PolicyContext) =>
  record(v) &&
  !!admitPolicyEvidence(v.reference) &&
  sameContext(v.reference, c) &&
  values(v.values);
export function admitGrantEvidence(v: any, c: PolicyContext): v is GrantEvidence {
  return (
    record(v) &&
    Object.keys(v).length === 5 &&
    v.contract_version === 1 &&
    sameContext(v, c) &&
    id(v.grant_id) &&
    hash(v.content_sha256)
  );
}
function grant(g: any, c: PolicyContext) {
  return (
    record(g) &&
    admitGrantEvidence(g.reference, c) &&
    id(g.service_identity_id) &&
    id(g.policy_id) &&
    pos(g.policy_version) &&
    ["active", "revoked"].includes(g.state) &&
    Array.isArray(g.actions) &&
    g.actions.length > 0 &&
    g.actions.length <= 5 &&
    new Set(g.actions).size === g.actions.length &&
    g.actions.every((a: any) => ["plan", "repair", "submit", "approve", "execute"].includes(a)) &&
    ["maximum_horizon_seconds", "maximum_contacts", "maximum_execution_concurrency"].every((k) =>
      pos(g[k]),
    ) &&
    cost({ max_estimated_cost_micros: g.maximum_estimated_cost_micros, currency: g.currency }) &&
    time(g.valid_from) &&
    time(g.valid_until) &&
    Date.parse(g.valid_from) < Date.parse(g.valid_until) &&
    time(g.approved_at) &&
    text(g.approval_reason, 4000) &&
    nullable(g.revoked_at, time) &&
    text(g.revocation_reason, 4000) &&
    (g.state === "active" ? g.revoked_at === null : g.revoked_at !== null)
  );
}
function page(v: any, n: number, check: (v: any) => boolean, key: (v: any) => string) {
  return (
    record(v) &&
    v.page === n &&
    typeof v.more === "boolean" &&
    Array.isArray(v.entries) &&
    v.entries.length <= 25 &&
    (!v.more || v.entries.length === 25) &&
    v.entries.every(check) &&
    new Set(v.entries.map(key)).size === v.entries.length
  );
}
export function admitPolicyModel(v: any, context?: PolicyContext): PolicyModel | null {
  if (
    !record(v) ||
    v.contract_version !== 1 ||
    !record(v.context) ||
    !id(v.context.organization_id) ||
    !id(v.context.mission_id) ||
    (context && !sameContext(v.context, context)) ||
    !record(v.query) ||
    Object.keys(v.query).length !== 2 ||
    ![v.query.grants_page, v.query.identities_page].every((n) => pos(n) && n <= 1_000_000)
  )
    return null;
  const c = { organization_id: v.context.organization_id, mission_id: v.context.mission_id };
  if (
    !nullable(v.current, (x) => version(x, c)) ||
    !nullable(v.active, (x) => version(x, c)) ||
    !values(v.defaults) ||
    !["unconfigured", "draft", "active", "retired"].includes(v.state) ||
    (v.current === null) !== (v.state === "unconfigured") ||
    (v.active !== null &&
      (!v.current ||
        v.active.reference.policy_id !== v.current.reference.policy_id ||
        v.active.reference.policy_version > v.current.reference.policy_version ||
        v.state !== "active")) ||
    !record(v.permissions) ||
    !["edit", "approve", "grants"].every((k) => typeof v.permissions[k] === "boolean") ||
    !page(
      v.grants,
      v.query.grants_page,
      (g) => grant(g, c),
      (g) => g.reference.grant_id,
    ) ||
    !nat(v.grants.active_count) ||
    !page(
      v.identities,
      v.query.identities_page,
      (r) => record(r) && id(r.id) && text(r.name) && r.name.length > 0,
      (r) => r.id,
    )
  )
    return null;
  return v as PolicyModel;
}
export function admitPolicyOperation(v: any, c: PolicyContext): PolicyOperation | null {
  if (
    !record(v) ||
    !pos(v.sequence) ||
    v.sequence > 1_000_000 ||
    !policyActions.includes(v.action) ||
    !record(v.input) ||
    !["completed", "rejected", "unconfirmed"].includes(v.status)
  )
    return null;
  if (v.status !== "completed") return v.receipt === null ? (v as PolicyOperation) : null;
  const receipt = v.receipt,
    r = receipt?.result,
    i = v.input;
  if (!record(receipt) || !id(receipt.receiptId) || !time(receipt.completedAt) || !record(r))
    return null;
  let valid = false;
  if (policyValidation(v.action))
    valid =
      r.valid === true &&
      r.actionId === v.action &&
      r.surfaceId === "fleet_planning_policy" &&
      Array.isArray(r.errors) &&
      r.errors.length === 0;
  if (v.action === "save-policy") {
    const base = i.edit_reference?.base;
    valid =
      sameContext(i.edit_reference, c) &&
      (base === null || (!!admitPolicyEvidence(base) && sameContext(base, c))) &&
      id(r.fleetPlanningPolicyId) &&
      r.fleetPlanningPolicyVersion === (base ? base.policy_version + 1 : 1) &&
      (!base || r.fleetPlanningPolicyId === base.policy_id) &&
      hash(r.contentSha256) &&
      r.currentVersion === r.fleetPlanningPolicyVersion &&
      ["draft", "active"].includes(r.lifecycleState);
  }
  if (v.action === "approve-policy") {
    const e = i.decision?.policy_evidence;
    valid =
      !!admitPolicyEvidence(e) &&
      sameContext(e, c) &&
      r.fleetPlanningPolicyId === e.policy_id &&
      r.fleetPlanningPolicyVersion === e.policy_version &&
      r.activeVersion === e.policy_version &&
      r.contentSha256 === e.content_sha256 &&
      r.lifecycleState === "active";
  }
  if (v.action === "issue-grant") {
    const e = i.policy_evidence;
    valid =
      !!admitPolicyEvidence(e) &&
      sameContext(e, c) &&
      id(r.automationGrantId) &&
      r.serviceIdentityId === i.grant?.service_identity_id &&
      r.lifecycleState === "active" &&
      r.fleetPlanningPolicyVersion === e.policy_version;
  }
  if (v.action === "revoke-grant")
    valid =
      admitGrantEvidence(i.grant_evidence, c) &&
      r.automationGrantId === i.grant_evidence.grant_id &&
      r.automationGrantId === i.revocation?.automation_grant_id &&
      r.lifecycleState === "revoked";
  return valid ? (v as PolicyOperation) : null;
}
export function admitPolicyPage(
  input: unknown,
  context?: PolicyContext,
  query?: PolicyModel["query"],
): PolicyPage | null {
  try {
    const bytes = JSON.stringify(input);
    if (new TextEncoder().encode(bytes).length > 180_000) return null;
    const v = JSON.parse(bytes);
    const model = admitPolicyModel(v?.model, context);
    if (
      !model ||
      !nat(v.sequence) ||
      v.sequence > 1_000_000 ||
      (query && !equalPolicyData(query, model.query))
    )
      return null;
    if (v.operation === null) return v.sequence === 0 ? v : null;
    const operation = admitPolicyOperation(v.operation, model.context);
    return operation && operation.sequence === v.sequence
      ? { model, sequence: v.sequence, operation }
      : null;
  } catch {
    return null;
  }
}
export function policyHref(model: PolicyModel, key: "grants_page" | "identities_page", n: number) {
  const query = { ...model.query, [key]: n };
  const params = new URLSearchParams();
  for (const k of ["grants_page", "identities_page"] as const)
    if (query[k] > 1) params.set(k, String(query[k]));
  const q = params.toString();
  return `/missions/${encodeURIComponent(model.context.mission_id)}/ops/planning/policy${q ? `?${q}` : ""}`;
}
export function duration(seconds: number): string {
  let remaining = seconds;
  const parts: string[] = [];
  for (const [unit, n] of [
    ["d", 86400],
    ["h", 3600],
    ["m", 60],
    ["s", 1],
  ] as const) {
    const count = Math.floor(remaining / n);
    if (count) parts.push(`${count}${unit}`);
    remaining %= n;
  }
  return parts.join(" ") || "0s";
}
