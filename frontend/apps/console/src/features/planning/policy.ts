import { decoders, request, type ApiResult, type Reader } from "@/api";
import {
  fromDocument,
  schemaFieldReader,
  toValue,
  visible,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";

/** Contract: docs/apogee/api/scheduling.md "Contact planning setup" (CP2). */
const { array, boolean, integer, nullable, object, string, timestamp, token } = decoders;

const doc: Reader<Readonly<Record<string, unknown>>> = (value, path = "") => {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw new decoders.DecodeError(path, "object");
  // Sound: a plain JSON object; values are read through the schema's paths.
  return value as Readonly<Record<string, unknown>>;
};
const fieldMeta = object({ path: string, group: token, advanced: boolean });

export const policyReader = (value: unknown, path = "") => {
  const raw = object({
    policy_id: nullable(token),
    version: nullable(integer),
    active_version: nullable(integer),
    document: nullable(doc),
    pending: nullable(
      object({
        version: integer,
        requested_by: nullable(object({ name: string })),
        requested_at: timestamp,
      }),
    ),
    schema: array(schemaFieldReader, 500),
    defaults: nullable(doc),
    permissions: array(token, 20),
  })(value, path);
  const meta = object({ schema: array(fieldMeta, 500) })(value, path).schema;
  return { ...raw, groups: meta };
};
export type Policy = ReturnType<typeof policyReader>;
export type PolicyGroup = Readonly<{
  key: string;
  fields: readonly SchemaField[];
  advanced: readonly SchemaField[];
}>;

const base = (missionId: string) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/policy`;

export function fetchPolicy(missionId: string, signal: AbortSignal): Promise<ApiResult<Policy>> {
  return request(base(missionId), policyReader, { signal });
}

export function savePolicy(
  missionId: string,
  body: Readonly<{ document: unknown; expected_version: number | null; reason: string }>,
) {
  const payload =
    body.expected_version === null ? { document: body.document, reason: body.reason } : body;
  return request(base(missionId), object({ version: integer, state: string }), {
    method: "POST",
    body: payload,
  });
}

export function decidePolicy(
  missionId: string,
  version: number,
  body: Readonly<{ decision: "approve" | "reject"; comment: string }>,
) {
  return request(
    `${base(missionId)}/${version}/decision`,
    object({ version: integer, state: string }),
    { method: "POST", body },
  );
}

/** Schema fields by group, in schema order; advanced fields separated (ux: collapsed). */
export function groups(policy: Policy): readonly PolicyGroup[] {
  const order: string[] = [];
  const byGroup = new Map<string, { fields: SchemaField[]; advanced: SchemaField[] }>();
  policy.schema.forEach((f, i) => {
    const meta = policy.groups[i];
    const key = meta?.group ?? "other";
    if (!byGroup.has(key)) {
      order.push(key);
      byGroup.set(key, { fields: [], advanced: [] });
    }
    (meta?.advanced ? byGroup.get(key)?.advanced : byGroup.get(key)?.fields)?.push(f);
  });
  return order.map((key) => ({
    key,
    fields: byGroup.get(key)?.fields ?? [],
    advanced: byGroup.get(key)?.advanced ?? [],
  }));
}

export function initialValues(policy: Policy): FormValues {
  return fromDocument(
    { kind: "policy", fields: policy.schema },
    policy.document ?? policy.defaults ?? {},
  );
}

/** The whole document from form values (POST takes the full document), or per-field problems. */
export function buildDocument(
  policy: Policy,
  values: FormValues,
): Readonly<
  { ok: true; document: Record<string, unknown> } | { ok: false; errors: Record<string, string> }
> {
  const document: Record<string, unknown> = {};
  const errors: Record<string, string> = {};
  for (const f of policy.schema) {
    if (!visible(f, values)) continue;
    const checked = toValue(f, values[f.path] ?? "");
    if (!checked.ok) {
      errors[f.path] = checked.message;
      continue;
    }
    const [group, ...rest] = f.path.split(".");
    if (!group || rest.length === 0) continue;
    const section = (document[group] ??= {}) as Record<string, unknown>;
    section[rest.join(".")] = checked.value;
  }
  return Object.keys(errors).length > 0 ? { ok: false, errors } : { ok: true, document };
}

export const groupTitles: Readonly<Record<string, string>> = {
  horizon: "Horizon",
  scoring: "Trade-offs",
  resources: "Resources",
  budgets: "Limits & budgets",
  redundancy: "Diversity",
  automation: "Mode",
};

/** One line for panels whose fields are all advanced (ux review: no empty panels). */
export const groupSummaries: Readonly<Record<string, string>> = {
  scoring:
    "How the scheduler weighs cost, priority and coverage against each other. The defaults suit most missions.",
};
