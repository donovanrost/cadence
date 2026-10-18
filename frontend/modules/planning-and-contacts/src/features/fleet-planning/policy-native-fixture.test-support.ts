import type { OpsFleetPlanningPolicyProps } from "./OpsFleetPlanningPolicy.contracts";
import { admitPolicyEditReference, admitPolicyEvidence } from "./policy-evidence";
import { required } from "./policy-test-helpers";

type Reader<T> = (value: unknown) => T;
type Shape = Record<string, Reader<unknown>>;
type Fields<S extends Shape> = { [K in keyof S]: ReturnType<S[K]> };
export function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw Error("Expected fixture object");
  return value as Record<string, unknown>;
}
function object<const S extends Shape>(shape: S): Reader<Fields<S>> {
  return (value) => {
    const input = record(value);
    // The mapped type describes exactly the keys whose readers ran above each value.
    return Object.fromEntries(
      Object.entries(shape).map(([key, read]) => [key, read(input[key])]),
    ) as Fields<S>;
  };
}
const text: Reader<string> = (value) => {
  if (typeof value !== "string") throw Error("Expected fixture text");
  return value;
};
const boolean: Reader<boolean> = (value) => {
  if (typeof value !== "boolean") throw Error("Expected fixture boolean");
  return value;
};
const number: Reader<number> = (value) => {
  if (typeof value !== "number" || !Number.isFinite(value)) throw Error("Expected fixture number");
  return value;
};
const nullable =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value) =>
    value === null ? null : read(value);
const array =
  <T>(read: Reader<T>): Reader<T[]> =>
  (value) => {
    if (!Array.isArray(value)) throw Error("Expected fixture array");
    return value.map(read);
  };
const oneOf =
  <const T extends string>(...choices: T[]): Reader<T> =>
  (value) => {
    const found = choices.find((choice) => choice === value);
    if (found === undefined) throw Error("Unexpected fixture choice");
    return found;
  };
const evidence = (value: unknown) => required(admitPolicyEvidence(value));
const reference = (value: unknown) => required(admitPolicyEditReference(value));
const option = object({ label: text, value: text });
const submit = object({ id: text, label: text });
const field = object({
  id: text,
  name: text,
  type: oneOf("text", "number", "select", "textarea"),
  label: text,
  required: boolean,
  min: nullable(number),
  options: array(option),
  value: text,
  errors: array(text),
});
const checkbox = object({
  id: text,
  name: text,
  type: oneOf("checkbox"),
  label: text,
  value: boolean,
  errors: array(text),
});

/** The optional Phoenix producer fixture crosses the same unknown boundary as JSON input. */
export const readNativePolicyProps: Reader<OpsFleetPlanningPolicyProps> = object({
  page: object({
    policy_evidence: nullable(evidence),
    back: object({ href: text, icon: text, label: text }),
    header: object({ eyebrow: text, title: text, copy: text }),
    state: object({ id: text, label: text, class: text }),
    manifest: object({
      id: text,
      version_label: text,
      content_sha256: nullable(text),
      sections: array(object({ title: text, facts: array(object({ term: text, value: text })) })),
      empty: nullable(object({ id: text, icon: text, title: text, copy: text })),
    }),
  }),
  policy_form: nullable(
    object({
      edit_reference: reference,
      panel_id: text,
      id: text,
      open: boolean,
      summary: text,
      fields: object({
        max_horizon_duration: field,
        requirement_concurrency: field,
        provider_search_concurrency: field,
        reuse_freshness_seconds: field,
        max_contacts: field,
        max_estimated_cost_micros: field,
        currency: field,
        critical_contact_reserve: field,
        automation_mode: field,
        execution_concurrency: field,
        max_repair_attempts: field,
        repair_horizon_duration: field,
        automatic_submission: checkbox,
        distinct_provider_required: checkbox,
        distinct_station_required: checkbox,
        distinct_service_pool_required: checkbox,
      }),
      redundancy: object({ id: text, summary: text }),
      submit,
    }),
  ),
  approval_form: nullable(
    object({ policy_evidence: evidence, panel_id: text, id: text, reason: field, submit }),
  ),
  authorization: object({
    organization_admin: boolean,
    admin_required: nullable(object({ copy: text })),
  }),
  grant_ledger: object({
    id: text,
    list_id: text,
    empty: object({ id: text, copy: text }),
    active_count: number,
    active_label: text,
  }),
  grant_form: nullable(
    object({
      policy_evidence: evidence,
      panel_id: text,
      id: text,
      fields: object({
        service_identity_id: field,
        maximum_horizon_duration: field,
        maximum_contacts: field,
        maximum_execution_concurrency: field,
        valid_days: field,
        approval_reason: field,
      }),
      submit,
    }),
  ),
  revocation_form: nullable(
    object({
      panel_id: text,
      id: text,
      fields: object({ automation_grant_id: field, reason: field }),
      submit,
    }),
  ),
  automation_grants: array(
    object({
      __dom_id: text,
      automation_grant_id: text,
      service_identity_id: text,
      lifecycle_state: text,
      lifecycle_state_class: text,
      policy_evidence: text,
      boundary: text,
      expiry: text,
    }),
  ),
});

export const readNativePolicyScenario = object({
  props: readNativePolicyProps,
  action: oneOf("approve-policy", "issue-grant", "save-policy"),
  values: (value) => {
    if (value === undefined) return {};
    return Object.fromEntries(
      Object.entries(record(value)).map(([key, value]) => [key, text(value)]),
    );
  },
});
