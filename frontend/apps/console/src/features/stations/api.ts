import type { MissionId } from "@/api/index.ts";
import { decoders, request, stationId, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §G1 (final contract in api/setup.md). */
const { array, integer, known, nullable, object, oneOf, string, token } = decoders;

const station = object({
  id: stationId,
  display_name: string,
  // free-text: the station's short code, an identifier.
  code: nullable(string),
  /** U25: a name stem the operator confirms; present only when `code` is null, never stored. */
  suggested_code: decoders.optional(nullable(string)),
  provider: nullable(string),
  region: nullable(string),
  lifecycle_state: oneOf(["active", "archived"]),
  // null: the model has no station↔transport link yet (api); the columns are hidden then.
  transport_count: nullable(integer),
  routing_rule_count: nullable(integer),
  health: nullable(
    object({ status: oneOf(["nominal", "degraded", "down"]), since: nullable(string) }),
  ),
});
export const stationsReader = object({ stations: array(station, 5000) });
export type Station = Decoded<typeof station>;

/** Active stations; with `includeArchived`, archived ones too, after them (ux U82, api). */
export async function fetchStations(
  missionId: MissionId,
  signal: AbortSignal,
  includeArchived = false,
): Promise<ApiResult<readonly Station[]>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/ground-stations${includeArchived ? "?include_archived=true" : ""}`,
    stationsReader,
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.stations } : result;
}

/** A provider check's result (L12): the row's last validate / sync. */
const check = object({
  status: nullable(known(["healthy", "failed"] as const)),
  checked_at: nullable(decoders.timestamp),
  // free-text: the provider's own error message, shown as is.
  error: nullable(string),
});

const provider = object({
  id: token,
  name: string,
  // free-text: an open vocabulary (provider adapter keys).
  provider_type: token,
  /** null exactly when grant is null: an older direct binding (api-ops drift sweep). */
  account: nullable(object({ id: token, name: nullable(string) })),
  status: object({
    lifecycle_state: known(["active", "archived"] as const),
    last_validated_at: nullable(decoders.timestamp),
    last_synced_at: nullable(decoders.timestamp),
  }),
  station_count: integer,
  // L12 (api-ops 4f81a1d0d, setup.md "Mission providers").
  version: integer,
  policy_mode: known(["approval_required", "bounded_automatic"] as const),
  /** null: bound before account grants (an old direct binding). */
  grant: nullable(
    object({ id: token, version: integer, state: known(["active", "revoked"] as const) }),
  ),
  health: object({ validate: check, sync: check }),
});
export type MissionProvider = Decoded<typeof provider>;
export const providerReader = provider;

export type MissionProviders = Readonly<{
  providers: readonly MissionProvider[];
  canManage: boolean;
}>;

/** `GET /missions/:id/providers`: `{providers, permissions}`; `providers.manage` gates the writes. */
export async function fetchProviders(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<MissionProviders>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/providers`,
    object({
      providers: array(provider, 500),
      permissions: array(known(["providers.manage"] as const), 10),
    }),
    { signal },
  );
  return result.ok
    ? {
        ok: true,
        value: {
          providers: result.value.providers,
          canManage: result.value.permissions.includes("providers.manage"),
        },
      }
    : result;
}
