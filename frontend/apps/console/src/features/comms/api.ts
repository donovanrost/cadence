import type { MissionId } from "@/api/index.ts";
import { decoders, jsonObject, request, spacecraftRef, type ApiResult, type Decoded } from "@/api";

/** Requested shapes: docs/apogee/plans/setup-shapes.md §T1/§T2 (final contract in api/setup.md). */
const { array, boolean, integer, nullable, object, oneOf, string, token } = decoders;

const direction = oneOf(["inbound", "outbound", "bidirectional"]);

const transport = object({
  id: token,
  display_name: string,
  version: integer,
  origin: oneOf(["direct", "provider_managed"]),
  // free-text: an open vocabulary (transport adapter kinds from the registry), shown as words.
  transport_kind: token,
  direction_capability: direction,
  lifecycle_state: oneOf(["active", "archived"]),
  station: nullable(object({ id: token, display_name: string })),
  routing_rule_count: integer,
});
export type Transport = Decoded<typeof transport>;

const role = oneOf(["primary", "candidate", "contributing"]);

const rule = object({
  id: token,
  display_name: string,
  purpose: nullable(string),
  direction,
  role,
  enabled: boolean,
  spacecraft: spacecraftRef,
  transport: object({ id: token, display_name: string, version: integer }),
});
export type RoutingRule = Decoded<typeof rule>;

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}`;

/** Active transports; with `includeArchived`, archived ones too, after them (ux U82, api). */
export async function fetchTransports(
  missionId: MissionId,
  signal: AbortSignal,
  includeArchived = false,
): Promise<ApiResult<readonly Transport[]>> {
  const result = await request(
    `${base(missionId)}/transports${includeArchived ? "?include_archived=true" : ""}`,
    object({ transports: array(transport, 5000) }),
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.transports } : result;
}

export const rulesReader = object({ rules: array(rule, 500), total: integer });
export type RulesPage = Decoded<typeof rulesReader>;

/** One group's rules (first 500); the groups read is the overview (pass-2 #10). */
export function fetchRoutingRules(
  key: Readonly<{ missionId: MissionId; transportId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<RulesPage>> {
  const query = new URLSearchParams({ transport_id: key.transportId, limit: "500" });
  return request(`${base(key.missionId)}/routing-rules?${query.toString()}`, rulesReader, {
    signal,
  });
}

const group = object({
  transport: object({ id: token, name: string }),
  direction,
  role,
  enabled_count: integer,
  disabled_count: integer,
  spacecraft_count: integer,
});
export type RoutingGroup = Decoded<typeof group>;

/** Active rules grouped by transport, direction and role, sorted by transport name. */
export async function fetchRoutingGroups(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<readonly RoutingGroup[]>> {
  const result = await request(
    `${base(missionId)}/routing-rules/groups`,
    object({ groups: array(group, 5000) }),
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.groups } : result;
}

/** A group's `?group=` query value: transport, direction and role. */
export function groupKey(g: Pick<RoutingGroup, "transport" | "direction" | "role">): string {
  return `${g.transport.id}~${g.direction}~${g.role}`;
}

export function directionLabel(d: Decoded<typeof direction>): string {
  return d === "inbound" ? "Downlink" : d === "outbound" ? "Uplink" : "Both";
}

const transportDetail = object({
  id: token,
  version: integer,
  lifecycle_state: oneOf(["active", "archived"]),
  // Field values are read through the kind schema's paths.
  document: jsonObject,
});
export type TransportDetail = Decoded<typeof transportDetail>;

export function fetchTransport(
  key: Readonly<{ missionId: MissionId; transportId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<TransportDetail>> {
  return request(
    `${base(key.missionId)}/transports/${encodeURIComponent(key.transportId)}`,
    transportDetail,
    { signal },
  );
}
