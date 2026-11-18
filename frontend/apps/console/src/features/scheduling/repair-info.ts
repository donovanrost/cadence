import { decoders as d, type Decoded } from "@/api/index.ts";

/**
 * U76 (api 1a5976482): what a re-plan started now would cover, on the plan detail read; null when
 * the plan can't be repaired (no source run). `cause` may be null even when one exists (api).
 */
export const repairInfoReader = d.object({
  window: d.object({ from: d.timestamp, to: d.timestamp }),
  horizon_seconds: d.integer,
  attempts: d.object({ used: d.integer, max: d.integer }),
  available: d.boolean,
  cause: d.nullable(
    d.object({
      kind: d.knownText(["provider_change", "station_outage"] as const),
      // free-text: the provider's display name
      provider_name: d.nullable(d.string),
      // free-text: the station's display name
      station_name: d.nullable(d.string),
      since: d.timestamp,
    }),
  ),
});
export type RepairInfo = Decoded<typeof repairInfoReader>;
