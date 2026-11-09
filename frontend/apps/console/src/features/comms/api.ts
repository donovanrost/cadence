import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shapes: docs/apogee/plans/setup-shapes.md §T1/§T2 (final contract in api/setup.md). */
const { array, boolean, integer, nullable, object, oneOf, string, token } = decoders;

const direction = oneOf(["inbound", "outbound", "bidirectional"]);

const transport = object({
  id: token,
  display_name: string,
  version: integer,
  origin: oneOf(["direct", "provider_managed"]),
  transport_kind: token,
  direction_capability: direction,
  lifecycle_state: oneOf(["active", "archived"]),
  station: nullable(object({ id: token, display_name: string })),
  routing_rule_count: integer,
});
export type Transport = Decoded<typeof transport>;

const rule = object({
  id: token,
  display_name: string,
  purpose: nullable(string),
  direction,
  role: oneOf(["primary", "candidate", "contributing"]),
  enabled: boolean,
  spacecraft: object({ id: token, name: string }),
  transport: object({ id: token, display_name: string, version: integer }),
});
export type RoutingRule = Decoded<typeof rule>;

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}`;

export async function fetchTransports(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly Transport[]>> {
  const result = await request(
    `${base(missionId)}/transports`,
    object({ transports: array(transport, 5000) }),
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.transports } : result;
}

export const rulesReader = object({ rules: array(rule, 500), total: integer });
export type RulesPage = Decoded<typeof rulesReader>;

/** First page only: routing is per spacecraft until DECISIONS #3, so this view stays minimal. */
export function fetchRoutingRules(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<RulesPage>> {
  return request(`${base(missionId)}/routing-rules?limit=100`, rulesReader, { signal });
}

export function directionLabel(d: Decoded<typeof direction>): string {
  return d === "inbound" ? "Downlink" : d === "outbound" ? "Uplink" : "Both";
}
