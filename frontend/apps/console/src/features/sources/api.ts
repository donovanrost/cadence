import type { MissionId } from "@/api/index.ts";
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

/** api-ops L11 (corrected 11-13): D1's kind, a closed set. */
export const sourceKinds = [
  "managed_tsdb",
  "byo_tsdb",
  "postgres",
  "object_archive",
  "projection",
] as const;
/** Registration (R1/W1) only offers these two. */
export const registerKinds = ["byo_tsdb", "managed_tsdb"] as const;
export const isolationLevels = [
  "shared",
  "customer_owned",
  "org_isolated",
  "mission_isolated",
] as const;
export const storages = ["questdb", "postgres_projection"] as const;
export const tsdbActions = ["provision", "reconcile", "deprovision"] as const;
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
  /** api-ops 888325a37: the backend jobs this source takes ([] unless a dedicated BYO TSDB). */
  tsdb_actions: optional(array(known(tsdbActions), 3)),
});
export type DataSource = Decoded<typeof source>;
export const sourceReader = source;

const listReader = object({
  sources: array(source, 1000),
  /** api-ops L11: ["data_sources.manage"] when the caller passes the writes' check; absent before L11. */
  permissions: optional(array(known(["data_sources.manage"] as const), 10)),
});
export type SourceList = Readonly<{ sources: readonly DataSource[]; canManage: boolean }>;

export async function fetchSources(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<SourceList>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/data-sources`,
    listReader,
    { signal },
  );
  return result.ok
    ? {
        ok: true,
        value: {
          sources: result.value.sources,
          canManage: result.value.permissions?.includes("data_sources.manage") ?? false,
        },
      }
    : result;
}
