/** Server snapshots have one owner; Vue drafts are separate mutable values. */
type ReadonlySnapshot<T> = T extends object
  ? { readonly [K in keyof T]: ReadonlySnapshot<T[K]> }
  : T;
import {
  admitPolicyEvidence,
  admitPolicyEditReference,
  type PolicyEvidence,
} from "./policy-evidence";
import type {
  OpsFleetPlanningPolicyEmits,
  PolicyFields,
  GrantFields,
} from "./OpsFleetPlanningPolicy.contracts";
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
export type PolicyContext = ReadonlySnapshot<{ organization_id: string; mission_id: string }>;
export type PolicyValues = ReadonlySnapshot<{
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
}>;
export type PolicyVersion = ReadonlySnapshot<{ reference: PolicyEvidence; values: PolicyValues }>;
export type GrantEvidence = ReadonlySnapshot<
  PolicyContext & {
    contract_version: 1;
    grant_id: string;
    content_sha256: string;
  }
>;
export type PolicyGrant = ReadonlySnapshot<{
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
}>;
export type PolicyModel = ReadonlySnapshot<{
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
}>;
export type PolicyInputs = {
  [A in PolicyAction]: OpsFleetPlanningPolicyEmits[A][0];
} & {
  "issue-grant": {
    grant: Record<string, string> & { service_identity_id: string };
    policy_evidence: PolicyEvidence;
  };
  "revoke-grant": OpsFleetPlanningPolicyEmits["revoke-grant"][0] & {
    grant_evidence: GrantEvidence;
  };
};
type ValidationResult<A extends "validate-policy" | "validate-grant"> = {
  valid: true;
  actionId: A;
  surfaceId: "fleet_planning_policy";
  errors: readonly [];
};
export type PolicyResults = {
  "validate-policy": ValidationResult<"validate-policy">;
  "validate-grant": ValidationResult<"validate-grant">;
  "save-policy": {
    fleetPlanningPolicyId: string;
    fleetPlanningPolicyVersion: number;
    contentSha256: string;
    currentVersion: number;
    lifecycleState: "draft" | "active";
  };
  "approve-policy": {
    fleetPlanningPolicyId: string;
    fleetPlanningPolicyVersion: number;
    contentSha256: string;
    activeVersion: number;
    lifecycleState: "active";
  };
  "issue-grant": {
    automationGrantId: string;
    serviceIdentityId: string;
    fleetPlanningPolicyVersion: number;
    lifecycleState: "active";
  };
  "revoke-grant": { automationGrantId: string; lifecycleState: "revoked" };
};
export type PolicyCommand = {
  [A in PolicyAction]: { action: A; input: PolicyInputs[A] };
}[PolicyAction];
export type SequencedPolicyCommand = PolicyCommand & { sequence: number };
export type CompletedPolicyOperation = ReadonlySnapshot<
  {
    [A in PolicyAction]: {
      sequence: number;
      action: A;
      input: PolicyInputs[A];
      status: "completed";
      receipt: { receiptId: string; completedAt: string; result: PolicyResults[A] };
    };
  }[PolicyAction]
>;
export type PolicyOperation = ReadonlySnapshot<
  | CompletedPolicyOperation
  | (SequencedPolicyCommand & { status: "rejected" | "unconfirmed"; receipt: null })
>;
export type PolicyPage = ReadonlySnapshot<{
  model: PolicyModel;
  sequence: number;
  operation: PolicyOperation | null;
}>;
export const equalPolicyData = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a, ordered) === JSON.stringify(b, ordered);
const ordered = (_: string, v: unknown) =>
  record(v)
    ? Object.fromEntries(
        Object.keys(v)
          .sort()
          .map((k) => [k, v[k]]),
      )
    : v;
const oneOf = <const T>(value: unknown, choices: readonly T[]): value is T =>
  choices.some((choice) => choice === value);
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max = 240): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  Array.from(v).every((character) => {
    const code = character.codePointAt(0) ?? 0;
    return (
      (code >= 32 || oneOf(code, [9, 10, 13])) &&
      code !== 127 &&
      !(code >= 0xd800 && code <= 0xdfff)
    );
  });
const id = (v: unknown): v is string => text(v) && v.length > 0 && !/\s/.test(v);
const hash = (v: unknown): v is string => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const nat = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
const pos = (v: unknown): v is number => nat(v) && v > 0;
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const nullable = <T>(v: unknown, check: (value: unknown) => value is T): v is T | null =>
  v === null || check(v);
const sameContext = (v: unknown, c: PolicyContext) =>
  record(v) && v.organization_id === c.organization_id && v.mission_id === c.mission_id;
const cost = (v: Record<string, unknown>) =>
  nullable(v.max_estimated_cost_micros, nat) &&
  nullable(v.currency, (c): c is string => typeof c === "string" && /^[A-Z]{3}$/.test(c)) &&
  (v.max_estimated_cost_micros === null || v.currency !== null);
function values(v: unknown): v is PolicyValues {
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
    oneOf(v.automation_mode, ["advisory", "approval_required", "bounded_automatic"])
  );
}
const version = (v: unknown, c: PolicyContext): v is PolicyVersion =>
  record(v) &&
  !!admitPolicyEvidence(v.reference) &&
  sameContext(v.reference, c) &&
  values(v.values);
export function admitGrantEvidence(v: unknown, c: PolicyContext): v is GrantEvidence {
  return (
    record(v) &&
    Object.keys(v).length === 5 &&
    v.contract_version === 1 &&
    sameContext(v, c) &&
    id(v.grant_id) &&
    hash(v.content_sha256)
  );
}
function grant(g: unknown, c: PolicyContext): g is PolicyGrant {
  return (
    record(g) &&
    admitGrantEvidence(g.reference, c) &&
    id(g.service_identity_id) &&
    id(g.policy_id) &&
    pos(g.policy_version) &&
    oneOf(g.state, ["active", "revoked"]) &&
    Array.isArray(g.actions) &&
    g.actions.length > 0 &&
    g.actions.length <= 5 &&
    new Set(g.actions).size === g.actions.length &&
    g.actions.every((a: unknown) => oneOf(a, ["plan", "repair", "submit", "approve", "execute"])) &&
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
function page<T>(
  v: unknown,
  n: number,
  check: (value: unknown) => value is T,
  key: (value: T) => string,
): v is Record<string, unknown> & { page: number; more: boolean; entries: T[] } {
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
function isPolicyModel(v: unknown, context?: PolicyContext): v is PolicyModel {
  if (
    !record(v) ||
    v.contract_version !== 1 ||
    !record(v.context) ||
    !id(v.context.organization_id) ||
    !id(v.context.mission_id) ||
    (context && !sameContext(v.context, context)) ||
    !record(v.query) ||
    Object.keys(v.query).length !== 2 ||
    !pos(v.query.grants_page) ||
    v.query.grants_page > 1_000_000 ||
    !pos(v.query.identities_page) ||
    v.query.identities_page > 1_000_000
  )
    return false;
  const c = { organization_id: v.context.organization_id, mission_id: v.context.mission_id };
  if (
    !nullable(v.current, (x) => version(x, c)) ||
    !nullable(v.active, (x) => version(x, c)) ||
    !values(v.defaults) ||
    !oneOf(v.state, ["unconfigured", "draft", "active", "retired"]) ||
    (v.current === null) !== (v.state === "unconfigured") ||
    (v.active !== null &&
      (!v.current ||
        v.active.reference.policy_id !== v.current.reference.policy_id ||
        v.active.reference.policy_version > v.current.reference.policy_version ||
        v.state !== "active")) ||
    !record(v.permissions) ||
    typeof v.permissions.edit !== "boolean" ||
    typeof v.permissions.approve !== "boolean" ||
    typeof v.permissions.grants !== "boolean" ||
    !page<PolicyGrant>(
      v.grants,
      v.query.grants_page,
      (g): g is PolicyGrant => grant(g, c),
      (g) => g.reference.grant_id,
    ) ||
    !nat(v.grants.active_count) ||
    !page<{ id: string; name: string }>(
      v.identities,
      v.query.identities_page,
      (r): r is { id: string; name: string } =>
        record(r) && id(r.id) && text(r.name) && r.name.length > 0,
      (r) => r.id,
    )
  )
    return false;
  return true;
}
export function admitPolicyModel(value: unknown, context?: PolicyContext): PolicyModel | null {
  return isPolicyModel(value, context) ? value : null;
}
const policyFieldKeys = [
  "max_horizon_duration",
  "requirement_concurrency",
  "provider_search_concurrency",
  "reuse_freshness_seconds",
  "max_contacts",
  "max_estimated_cost_micros",
  "currency",
  "critical_contact_reserve",
  "automation_mode",
  "execution_concurrency",
  "max_repair_attempts",
  "repair_horizon_duration",
  "automatic_submission",
  "distinct_provider_required",
  "distinct_station_required",
  "distinct_service_pool_required",
] as const satisfies readonly (keyof PolicyFields)[];
const grantFieldKeys = [
  "service_identity_id",
  "maximum_horizon_duration",
  "maximum_contacts",
  "maximum_execution_concurrency",
  "valid_days",
  "approval_reason",
] as const satisfies readonly (keyof GrantFields)[];

export function admitPolicyCommand(
  action: unknown,
  input: unknown,
  context: PolicyContext,
): PolicyCommand | null {
  if (!record(input)) return null;
  switch (action) {
    case "validate-policy":
    case "save-policy": {
      const reference = admitPolicyEditReference(input.edit_reference);
      if (
        !stringFields(input.policy, policyFieldKeys) ||
        !reference ||
        !sameContext(reference, context)
      )
        return null;
      return { action, input: { ...input, policy: input.policy, edit_reference: reference } };
    }
    case "approve-policy": {
      const decision = input.decision;
      if (!record(decision) || typeof decision.reason !== "string") return null;
      const evidence = admitPolicyEvidence(decision.policy_evidence);
      if (!evidence || !sameContext(evidence, context)) return null;
      return {
        action,
        input: {
          ...input,
          decision: { ...decision, reason: decision.reason, policy_evidence: evidence },
        },
      };
    }
    case "validate-grant":
      return stringFields(input.grant, grantFieldKeys)
        ? { action, input: { ...input, grant: input.grant } }
        : null;
    case "issue-grant": {
      const evidence = admitPolicyEvidence(input.policy_evidence);
      if (
        !stringFields(input.grant, grantFieldKeys) ||
        typeof input.grant.service_identity_id !== "string" ||
        !evidence ||
        !sameContext(evidence, context)
      )
        return null;
      return {
        action,
        input: {
          ...input,
          grant: { ...input.grant, service_identity_id: input.grant.service_identity_id },
          policy_evidence: evidence,
        },
      };
    }
    case "revoke-grant": {
      const revocation = input.revocation;
      if (
        !record(revocation) ||
        typeof revocation.automation_grant_id !== "string" ||
        typeof revocation.reason !== "string" ||
        !admitGrantEvidence(input.grant_evidence, context)
      )
        return null;
      return {
        action,
        input: {
          ...input,
          revocation: {
            ...revocation,
            automation_grant_id: revocation.automation_grant_id,
            reason: revocation.reason,
          },
          grant_evidence: input.grant_evidence,
        },
      };
    }
    default:
      return null;
  }
}
const stringFields = <K extends string>(
  value: unknown,
  keys: readonly K[],
): value is Record<K, string> =>
  record(value) &&
  keys.every((key) => typeof value[key] === "string") &&
  Object.values(value).every((field) => typeof field === "string");

export function admitPolicyOperation(
  value: unknown,
  context: PolicyContext,
): PolicyOperation | null {
  if (!record(value) || !pos(value.sequence) || value.sequence > 1_000_000) return null;
  const command = admitPolicyCommand(value.action, value.input, context);
  if (!command) return null;
  const sequence = value.sequence;
  if (value.status === "rejected" || value.status === "unconfirmed")
    return value.receipt === null
      ? { ...command, sequence, status: value.status, receipt: null }
      : null;
  if (value.status !== "completed" || !record(value.receipt)) return null;
  const { receiptId, completedAt, result } = value.receipt;
  if (!id(receiptId) || !time(completedAt) || !record(result)) return null;
  const completed = { sequence, status: "completed" as const };
  switch (command.action) {
    case "validate-policy":
    case "validate-grant":
      if (
        result.valid !== true ||
        result.actionId !== command.action ||
        result.surfaceId !== "fleet_planning_policy" ||
        !Array.isArray(result.errors) ||
        result.errors.length !== 0
      )
        return null;
      // Branching here keeps actionId correlated with the operation discriminant.
      if (command.action === "validate-policy")
        return {
          ...command,
          ...completed,
          receipt: {
            receiptId,
            completedAt,
            result: {
              ...result,
              valid: true,
              actionId: command.action,
              surfaceId: "fleet_planning_policy",
              errors: [],
            },
          },
        };
      return {
        ...command,
        ...completed,
        receipt: {
          receiptId,
          completedAt,
          result: {
            ...result,
            valid: true,
            actionId: command.action,
            surfaceId: "fleet_planning_policy",
            errors: [],
          },
        },
      };
    case "save-policy": {
      const base = command.input.edit_reference.base;
      const {
        fleetPlanningPolicyId,
        fleetPlanningPolicyVersion,
        contentSha256,
        currentVersion,
        lifecycleState,
      } = result;
      if (
        !id(fleetPlanningPolicyId) ||
        !pos(fleetPlanningPolicyVersion) ||
        fleetPlanningPolicyVersion !== (base ? base.policy_version + 1 : 1) ||
        (base && fleetPlanningPolicyId !== base.policy_id) ||
        !hash(contentSha256) ||
        currentVersion !== fleetPlanningPolicyVersion ||
        !oneOf(lifecycleState, ["draft", "active"])
      )
        return null;
      return {
        ...command,
        ...completed,
        receipt: {
          receiptId,
          completedAt,
          result: {
            ...result,
            fleetPlanningPolicyId,
            fleetPlanningPolicyVersion,
            contentSha256,
            currentVersion,
            lifecycleState,
          },
        },
      };
    }
    case "approve-policy": {
      const evidence = command.input.decision.policy_evidence;
      const {
        fleetPlanningPolicyId,
        fleetPlanningPolicyVersion,
        contentSha256,
        activeVersion,
        lifecycleState,
      } = result;
      if (
        fleetPlanningPolicyId !== evidence.policy_id ||
        fleetPlanningPolicyVersion !== evidence.policy_version ||
        activeVersion !== evidence.policy_version ||
        contentSha256 !== evidence.content_sha256 ||
        lifecycleState !== "active"
      )
        return null;
      return {
        ...command,
        ...completed,
        receipt: {
          receiptId,
          completedAt,
          result: {
            ...result,
            fleetPlanningPolicyId,
            fleetPlanningPolicyVersion,
            contentSha256,
            activeVersion,
            lifecycleState,
          },
        },
      };
    }
    case "issue-grant": {
      const { automationGrantId, serviceIdentityId, fleetPlanningPolicyVersion, lifecycleState } =
        result;
      if (
        !id(automationGrantId) ||
        serviceIdentityId !== command.input.grant.service_identity_id ||
        lifecycleState !== "active" ||
        fleetPlanningPolicyVersion !== command.input.policy_evidence.policy_version
      )
        return null;
      return {
        ...command,
        ...completed,
        receipt: {
          receiptId,
          completedAt,
          result: {
            ...result,
            automationGrantId,
            serviceIdentityId,
            fleetPlanningPolicyVersion,
            lifecycleState,
          },
        },
      };
    }
    case "revoke-grant": {
      const { automationGrantId, lifecycleState } = result;
      if (
        automationGrantId !== command.input.grant_evidence.grant_id ||
        automationGrantId !== command.input.revocation.automation_grant_id ||
        lifecycleState !== "revoked"
      )
        return null;
      return {
        ...command,
        ...completed,
        receipt: {
          receiptId,
          completedAt,
          result: { ...result, automationGrantId, lifecycleState },
        },
      };
    }
  }
}
export function admitPolicyPage(
  input: unknown,
  context?: PolicyContext,
  query?: PolicyModel["query"],
): PolicyPage | null {
  try {
    const bytes = JSON.stringify(input);
    if (new TextEncoder().encode(bytes).length > 180_000) return null;
    const v: unknown = JSON.parse(bytes);
    if (!record(v)) return null;
    const model = admitPolicyModel(v.model, context);
    if (
      !model ||
      !nat(v.sequence) ||
      v.sequence > 1_000_000 ||
      (query && !equalPolicyData(query, model.query))
    )
      return null;
    if (v.operation === null)
      return v.sequence === 0 ? { model, sequence: 0, operation: null } : null;
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
