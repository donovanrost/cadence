import type { RouteLocationRaw } from "vue-router";
import type { Scid } from "@/api/index.ts";

/** The sample a link names: an alarm's trigger, or an episode event's sample (U68 R5, D1 part A). */
export type SampleRef = Readonly<{
  id: string | null;
  at: string;
  receipt_time?: string | null | undefined;
}>;

/**
 * ux U71 A7 / U80: Telemetry on the point, centred and ringed at the sample's time, with the
 * Sample aside open on it (`sample`, and `received` when known, which makes the read exact). A
 * sample with no id (catalog monitoring) only rings the time.
 */
export function sampleLink(scid: Scid, pointId: string, s: SampleRef): RouteLocationRaw {
  return {
    name: "ops.spacecraft",
    params: { scId: scid, tab: "telemetry" },
    query: {
      points: pointId,
      focus: pointId,
      at: s.at,
      ...(s.id ? { sample: s.id, ...(s.receipt_time ? { received: s.receipt_time } : {}) } : {}),
    },
  };
}
