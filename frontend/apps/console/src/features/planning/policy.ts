import type { MissionId } from "@/api/index.ts";
import {
  actor,
  childRecord,
  decoders,
  jsonObject,
  recordOf,
  request,
  type ApiResult,
  type Reader,
} from "@/api";
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

const doc: Reader<Readonly<Record<string, unknown>>> = jsonObject;
/** What a policy save or decision answers (Control.PlanningPolicy). */
export const policyVersionStates = ["pending_approval", "active", "rejected"] as const;
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
        requested_by: nullable(actor),
        requested_at: timestamp,
        // free-text: the saver's note (api 7e454da56), trimmed, at most 500 characters; null when none.
        reason: nullable(string),
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

const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/policy`;

export function fetchPolicy(missionId: MissionId, signal: AbortSignal): Promise<ApiResult<Policy>> {
  return request(base(missionId), policyReader, { signal });
}

export function savePolicy(
  missionId: MissionId,
  body: Readonly<{ document: unknown; expected_version: number | null; reason: string }>,
) {
  // A first save has no version to expect; an empty reason means none (api 7e454da56).
  const payload = {
    document: body.document,
    ...(body.expected_version === null ? {} : { expected_version: body.expected_version }),
    ...(body.reason === "" ? {} : { reason: body.reason }),
  };
  return request(
    base(missionId),
    object({ version: integer, state: decoders.known(policyVersionStates) }),
    {
      method: "POST",
      body: payload,
    },
  );
}

export function decidePolicy(
  missionId: MissionId,
  version: number,
  body: Readonly<{ decision: "approve" | "reject"; comment: string }>,
) {
  return request(
    `${base(missionId)}/${version}/decision`,
    object({ version: integer, state: decoders.known(policyVersionStates) }),
    { method: "POST", body },
  );
}

/**
 * DECISIONS #63 / U34: billing is out of scope, so money fields are hidden. They stay in the schema
 * and form values, so a save sends their server values back unchanged.
 */
export const hiddenMoneyPaths: ReadonlySet<string> = new Set([
  "budgets.max_estimated_cost_micros",
  "budgets.currency",
  "budgets.critical_cost_reserve_micros",
  "scoring.cost_efficiency_weight",
]);

/** Shown schema fields by group, in schema order; advanced separated (ux: collapsed). No empty groups. */
export function groups(policy: Policy): readonly PolicyGroup[] {
  const order: string[] = [];
  const byGroup = new Map<string, { fields: SchemaField[]; advanced: SchemaField[] }>();
  policy.schema.forEach((f, i) => {
    if (hiddenMoneyPaths.has(f.path)) return;
    const meta = policy.groups[i];
    const key = meta?.group ?? "other";
    if (!byGroup.has(key)) {
      order.push(key);
      byGroup.set(key, { fields: [], advanced: [] });
    }
    (meta?.advanced ? byGroup.get(key)?.advanced : byGroup.get(key)?.fields)?.push(f);
  });
  return order
    .map((key) => ({
      key,
      fields: byGroup.get(key)?.fields ?? [],
      advanced: byGroup.get(key)?.advanced ?? [],
    }))
    .filter((g) => g.fields.length > 0 || g.advanced.length > 0);
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
  const stored = policy.document ?? policy.defaults ?? {};
  for (const f of policy.schema) {
    const [group, ...rest] = f.path.split(".");
    if (!group || rest.length === 0) continue;
    const put = (v: unknown) => {
      childRecord(document, group)[rest.join(".")] = v;
    };
    // U34: hidden money fields go back exactly as stored; never validated, since no one can see them.
    if (hiddenMoneyPaths.has(f.path)) {
      const v = recordOf(stored[group])?.[rest.join(".")];
      if (v !== undefined) put(v);
      continue;
    }
    if (!visible(f, values)) continue;
    const checked = toValue(f, values[f.path] ?? "");
    if (!checked.ok) {
      errors[f.path] = checked.message;
      continue;
    }
    put(checked.value);
  }
  return Object.keys(errors).length > 0 ? { ok: false, errors } : { ok: true, document };
}

// keyed-by-text: schema group keys, an open set from the server's form layout; an unknown group shows its key
export const groupTitles: Readonly<Record<string, string>> = {
  horizon: "Horizon",
  scoring: "Trade-offs",
  resources: "Resources",
  budgets: "Limits & reserves",
  redundancy: "Diversity",
  automation: "Mode",
};

/** One line for panels whose fields are all advanced (ux review: no empty panels). */
// keyed-by-text: schema group keys from the policy schema's layout; only some groups have a summary
export const groupSummaries: Readonly<Record<string, string>> = {
  scoring:
    "How the scheduler weighs priority, deadlines and coverage against each other. The defaults suit most missions.",
};

/** The saver's note (api): at most 500 characters once trimmed. */
export const REASON_MAX = 500;

/**
 * ux U20: "Policy v4 was proposed by Mira K. at 11-14 02:10Z: <reason>." The sentence ends at the time
 * when there's no reason, and leaves out "by" when the saver isn't known.
 */
export function pendingLine(
  pending: Readonly<{
    version: number;
    requested_by: Readonly<{ name: string | null }> | null;
    reason: string | null;
  }>,
  at: string,
): string {
  const name = pending.requested_by?.name;
  const who = name ? ` by ${name}` : "";
  const line = `Policy v${pending.version} was proposed${who} at ${at}`;
  if (!pending.reason) return `${line}.`;
  // The reason is the saver's own sentence: don't double its full stop.
  return `${line}: ${pending.reason}${/[.!?]$/.test(pending.reason) ? "" : "."}`;
}
