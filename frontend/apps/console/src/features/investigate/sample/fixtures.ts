import { decode } from "@/api/index.ts";
import { sampleReadReader } from "./api.ts";

type Patch = Readonly<Record<string, unknown>>;
const source = {
  realm: "flight",
  data_source_id: "ds-1",
  data_source_name: "Ground history",
  source_binding_id: "b-1",
  binding_label: "Earendil telemetry",
  binding_version: 3,
  source_endpoint_id: "ep-1",
  endpoint_label: "Fairbanks",
  replay_run_id: null,
  replay_run_label: null,
};
const record = {
  packet_id: "p-1",
  evidence_id: "ev-1",
  packet_definition_id: "pd-1",
  packet_definition_name: "HK_EPS",
  packet_definition_version: 4,
  validity_state: "canonical",
};
const sample = {
  point_id: "EPS.VBAT",
  point_name: "Battery voltage",
  sample_id: "s-1",
  spacecraft_id: "sc-312",
  receipt_time: "2026-11-08T02:08:12.880Z",
  generation_time: "2026-11-08T02:08:11.204Z",
  quality: "good",
  raw_value: { state: "ready", text: "0x1F40", format: "hex" },
  engineering_value: { state: "ready", text: "28.1", format: null },
  engineering_unit: "V",
};

/** A ready read through the decoder, with `over` / `src` / `rec` laid over the sample's parts. */
export function readySample(over: Patch = {}, src: Patch = {}, rec: Patch = {}) {
  const r = decode(sampleReadReader, {
    status: "ready",
    sample: {
      ...sample,
      ...over,
      source: { ...source, ...src },
      record: { ...record, ...rec },
    },
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}

export function statusOnly(status: string) {
  const r = decode(sampleReadReader, { status, sample: null });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}

/** The decoded sample of a ready read (tests of the row words). */
export function sampleOf(over: Patch = {}, src: Patch = {}, rec: Patch = {}) {
  const s = readySample(over, src, rec).sample;
  if (!s) throw new Error("no sample");
  return s;
}
