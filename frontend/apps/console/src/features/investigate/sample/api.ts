import type { PointId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Decoded,
  type SpacecraftId,
  pointId as pointIdReader,
} from "@/api/index.ts";

/**
 * api D1: one telemetry sample, for Investigate's Sample aside and its Technical details. Every
 * name and label is null when it can't be resolved (ux U25: drop it, never show the id instead).
 */
const valueReader = d.object({
  state: d.knownText(["ready", "not_recorded", "limited", "unsupported"] as const),
  // free-text: the value as the projection writes it (only when state is ready)
  text: d.nullable(d.string),
  format: d.nullable(d.knownText(["json", "hex"] as const)),
});
export type SampleValue = Decoded<typeof valueReader>;

const sourceReader = d.object({
  realm: d.knownText(["flight", "rehearsal", "replay", "simulation"] as const),
  data_source_id: d.nullable(d.token),
  // free-text: the data source's name
  data_source_name: d.nullable(d.string),
  source_binding_id: d.nullable(d.token),
  // free-text: the binding's label
  binding_label: d.nullable(d.string),
  binding_version: d.nullable(d.integer),
  source_endpoint_id: d.nullable(d.token),
  // free-text: the endpoint's label
  endpoint_label: d.nullable(d.string),
  replay_run_id: d.nullable(d.token),
  // free-text: the replay run's label
  replay_run_label: d.nullable(d.string),
});

const recordReader = d.object({
  packet_id: d.nullable(d.token),
  evidence_id: d.nullable(d.token),
  packet_definition_id: d.nullable(d.token),
  // free-text: the packet definition's name
  packet_definition_name: d.nullable(d.string),
  packet_definition_version: d.nullable(d.integer),
  validity_state: d.nullable(
    d.knownText(["canonical", "duplicate", "conflict", "superseded", "advisory"] as const),
  ),
});

const sampleReader = d.object({
  point_id: pointIdReader,
  // free-text: the point's catalog name
  point_name: d.nullable(d.string),
  sample_id: d.token,
  spacecraft_id: spacecraftIdReader,
  receipt_time: d.timestamp,
  generation_time: d.nullable(d.timestamp),
  quality: d.knownText(["good", "suspect", "bad"] as const),
  raw_value: valueReader,
  engineering_value: valueReader,
  // free-text: the point's engineering unit from its catalog definition
  engineering_unit: d.nullable(d.string),
  source: sourceReader,
  record: recordReader,
});
export type Sample = Decoded<typeof sampleReader>;

export const sampleStatuses = [
  "ready",
  "not_found",
  "ambiguous",
  "timeout",
  "unsupported",
  "unavailable",
] as const;

/** `sample` is null unless the status is ready. */
export const sampleReadReader = d.object({
  status: d.knownText(sampleStatuses),
  sample: d.nullable(sampleReader),
});
export type SampleRead = Decoded<typeof sampleReadReader>;

export type SampleKey = Readonly<{
  sampleId: string;
  pointId: PointId;
  spacecraftId: SpacecraftId;
  /** The exact match (±1 s on the receipt clock). */
  receiptTime: string | null;
  /** Without a receipt time: the sample's generation time, so api searches ±60 s, not 24 h. */
  at: string | null;
}>;

/** The read's path and query: receipt_time when known, else at when known, else neither. */
export function samplePath(missionId: MissionId, key: SampleKey): string {
  const query = new URLSearchParams({ point_id: key.pointId, spacecraft_id: key.spacecraftId });
  if (key.receiptTime) query.set("receipt_time", key.receiptTime);
  else if (key.at) query.set("at", key.at);
  const sample = encodeURIComponent(key.sampleId);
  return `/missions/${encodeURIComponent(missionId)}/telemetry/samples/${sample}?${query}`;
}

export function fetchSample(
  missionId: MissionId,
  key: SampleKey,
  signal?: AbortSignal,
): Promise<ApiResult<SampleRead>> {
  return request(samplePath(missionId, key), sampleReadReader, signal ? { signal } : {});
}
