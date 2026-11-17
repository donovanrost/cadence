import type { MissionId } from "@/api/index.ts";
import {
  decoders,
  isKnown,
  request,
  scid as scidReader,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Decoded,
  type Reader,
  type SpacecraftId,
} from "@/api";
import type { ApKeyValueItem } from "@/ui";
import type { ApCheckRow as CheckRow } from "@/ui";
import { telemetryFreshness } from "./api.ts";
import { heardLabel, orbitLabel } from "./format.ts";

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
  // No version: a route names the transport and the current version resolves at apply (DECISIONS #104).
  transport: object({ id: token, name: string }),
});
/** Readiness checks (Reads.SpacecraftDetail); a new one reads as its key. */
const readinessKeys = ["identity", "profile", "routing", "telemetry"] as const;
const check = object({
  key: decoders.knownText(readinessKeys),
  status: oneOf(checkStatuses),
  title: string,
  body: string,
});

/** `ready` is the server's (no blocker in identity, profile, routing); a disagreement isn't a failed read (qa 11-13). */
export const detailReader = object({
  spacecraft: object({
    id: spacecraftIdReader,
    name: string,
    scid: nullable(scidReader),
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
  /** L22 (api 8243895f1): the running switches from the active configuration; null = unknown. */
  commanding_enabled: decoders.optional(nullable(boolean)),
  telemetry_enabled: decoders.optional(nullable(boolean)),
  telemetry: telemetryFreshness,
  routing_rules: array(rule, 1000),
  readiness: object({ ready: boolean, checks: array(check, 20) }),
});

export type SpacecraftDetail = Decoded<typeof detailReader>;
export type RoutingRule = SpacecraftDetail["routing_rules"][number];
export type ReadinessCheck = SpacecraftDetail["readiness"]["checks"][number];

export function fetchSpacecraftDetail(
  key: Readonly<{ missionId: MissionId; spacecraftId: SpacecraftId }>,
  signal: AbortSignal,
): Promise<ApiResult<SpacecraftDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/spacecraft/${encodeURIComponent(key.spacecraftId)}`,
    detailReader,
    { signal },
  );
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

export function identityFacts(detail: SpacecraftDetail, now: Date): readonly ApKeyValueItem[] {
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
      value: orbitLabel(sc.plane, sc.slot) ?? "Not set",
      mono: sc.plane !== null,
    },
    {
      key: "heard",
      label: "Last heard",
      value:
        sc.last_received_at !== null
          ? heardLabel(sc.last_received_at, now)
          : detail.telemetry === "degraded"
            ? "Not known right now (history unavailable)"
            : "Awaiting first AOS",
      mono: sc.last_received_at !== null,
    },
  ];
}

const checkLabels: Readonly<Record<(typeof readinessKeys)[number], string>> = {
  identity: "Identity",
  profile: "Profile",
  routing: "Routing",
  telemetry: "Telemetry",
};

/** Server checks as check rows: the title is the sentence, the body its detail. */
export function checkRows(checks: readonly ReadinessCheck[]): readonly CheckRow[] {
  return checks.map((check) => {
    const verdict = ((): Pick<CheckRow, "state" | "verdict"> => {
      switch (check.status) {
        case "ready":
          return { state: "nominal", verdict: "Pass" };
        case "blocker":
          return { state: "crit", verdict: "Blocker" };
        case "caution":
          return { state: "caution", verdict: "Caution" };
        case "not_set_up":
          return { state: "caution", verdict: "Note" };
      }
    })();
    return {
      key: isKnown(check.key) ? check.key : check.key.unrecognized,
      label: isKnown(check.key) ? checkLabels[check.key] : check.key.unrecognized,
      sentence: check.title,
      detail: check.body,
      ...verdict,
    };
  });
}
