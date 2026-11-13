import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:id/data-sources` (D1). */
const {
  array,
  boolean,
  integer,
  known,
  nullable,
  object,
  oneOf,
  optional,
  string,
  timestamp,
  token,
} = decoders;

/** api-ops L11: a closed enum. */
export const sourceKinds = ["byo_tsdb", "managed_tsdb"] as const;
export const isolationLevels = [
  "shared",
  "customer_owned",
  "org_isolated",
  "mission_isolated",
] as const;
export const storages = ["questdb", "postgres_projection"] as const;
const option = object({ key: token, label: string });

export const healthReader = nullable(
  object({ status: oneOf(["healthy", "degraded", "unknown"]), checked_at: nullable(timestamp) }),
);

const source = object({
  id: token,
  display_name: string,
  kind: known(sourceKinds),
  owner: token,
  health: healthReader,
  last_received_at: nullable(timestamp),
  expected_interval_s: nullable(integer),
  stale: nullable(boolean),
  credentials: nullable(
    object({
      status: oneOf(["valid", "expiring", "expired", "none"]),
      rotated_at: nullable(timestamp),
    }),
  ),
  // L11 additions (api-ops, agreed 11-13). Optional until they ship, so today's D1 still reads.
  state: optional(known(["enabled", "disabled"] as const)),
  logical_source: optional(nullable(option)),
  isolation_level: optional(known(isolationLevels)),
  storage: optional(nullable(known(storages))),
  // free-text: a masked secret reference ("secret://…/primary"), shown as is; never the material.
  credentials_ref: optional(nullable(string)),
  /** A platform-shared source: platform admins change it in admin mode; read-only here. */
  shared: optional(boolean),
});
export type DataSource = Decoded<typeof source>;
export const sourceReader = source;

export async function fetchSources(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly DataSource[]>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/data-sources`,
    object({ sources: array(source, 1000) }),
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.sources } : result;
}
