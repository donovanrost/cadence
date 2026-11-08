import { decoders, request, type ApiResult, type Reader } from "@/api";
import { formatShort, type ApKeyValueItem, type OpState } from "@/ui";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:mission_id/spacecraft/:spacecraft_id`. */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const checkStatuses = ["ready", "blocker", "caution", "not_set_up"] as const;
export type CheckStatus = (typeof checkStatuses)[number];
const directions = ["inbound", "outbound", "bidirectional"] as const;
export type Direction = (typeof directions)[number];

const nullOnly: Reader<null> = (value, path = "") => {
  // v1: configuration arrives with change sets (DECISIONS #1); a value here needs a new decoder.
  if (value !== null) throw new decoders.DecodeError(path, "null (configuration not in v1)");
  return null;
};

const rule = object({
  id: token,
  name: string,
  purpose: nullable(string),
  direction: oneOf(directions),
  role: oneOf(["primary", "candidate", "contributing"]),
  enabled: boolean,
  active: boolean,
  transport: object({ id: token, name: string, version: integer }),
});
const check = object({ key: token, status: oneOf(checkStatuses), title: string, body: string });

export const detailReader = (value: unknown, path = "") => {
  const raw = object({
    spacecraft: object({
      id: token,
      name: string,
      scid: nullable(integer),
      norad_id: nullable(integer),
      plane: nullable(integer),
      slot: nullable(integer),
      last_received_at: nullable(timestamp),
    }),
    profile: nullable(
      object({
        id: token,
        name: nullable(string),
        version: integer,
        latest_version: nullable(integer),
      }),
    ),
    configuration: nullOnly,
    routing_rules: array(rule, 1000),
    readiness: object({ ready: boolean, checks: array(check, 20) }),
  })(value, path);
  const gating = raw.readiness.checks.filter((c) => c.key !== "telemetry");
  if (raw.readiness.ready !== gating.every((c) => c.status !== "blocker"))
    throw new decoders.DecodeError(
      `${path ? `${path}.` : ""}readiness.ready`,
      "agreement with checks",
    );
  return raw;
};

export type SpacecraftDetail = ReturnType<typeof detailReader>;
export type RoutingRule = SpacecraftDetail["routing_rules"][number];
export type ReadinessCheck = SpacecraftDetail["readiness"]["checks"][number];

export function fetchSpacecraftDetail(
  key: Readonly<{ missionId: string; spacecraftId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<SpacecraftDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/spacecraft/${encodeURIComponent(key.spacecraftId)}`,
    detailReader,
    { signal },
  );
}

export function checkState(status: CheckStatus): OpState {
  switch (status) {
    case "ready":
      return "nominal";
    case "blocker":
      return "crit";
    case "caution":
      return "caution";
    case "not_set_up":
      return "off";
  }
}

export function directionLabel(direction: Direction): string {
  switch (direction) {
    case "inbound":
      return "Downlink";
    case "outbound":
      return "Uplink";
    case "bidirectional":
      return "Both";
  }
}

export function identityFacts(detail: SpacecraftDetail): readonly ApKeyValueItem[] {
  const sc = detail.spacecraft;
  return [
    {
      key: "scid",
      label: "SCID",
      value: sc.scid === null ? "Not set" : String(sc.scid),
      mono: true,
    },
    {
      key: "norad",
      label: "NORAD id",
      value: sc.norad_id === null ? "Not set" : String(sc.norad_id),
      mono: true,
    },
    {
      key: "orbit",
      label: "Orbit",
      value:
        sc.plane === null
          ? "Not set"
          : `Plane ${sc.plane}${sc.slot === null ? "" : ` · slot ${sc.slot}`}`,
    },
    {
      key: "heard",
      label: "Last heard",
      value:
        sc.last_received_at === null
          ? "Awaiting first AOS"
          : formatShort(new Date(sc.last_received_at)),
      mono: sc.last_received_at !== null,
    },
  ];
}
