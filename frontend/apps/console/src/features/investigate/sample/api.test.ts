import { describe, expect, it } from "vite-plus/test";
import {
  decode,
  decoders as d,
  isKnown,
  missionId,
  spacecraftId,
  pointId as pointIdReader,
} from "@/api/index.ts";
import { sampleReadReader, samplePath } from "./api.ts";

const ready = () => ({
  status: "ready",
  sample: {
    point_id: pointIdReader("EPS.VBAT"),
    point_name: null,
    sample_id: "s-1",
    spacecraft_id: "sc-312",
    receipt_time: "2026-11-08T02:08:11.250Z",
    generation_time: "2026-11-08T02:08:11Z",
    quality: "suspect",
    raw_value: { state: "ready", text: "0x1F", format: "hex" },
    engineering_value: { state: "limited", text: null, format: null },
    engineering_unit: "V",
    source: {
      realm: "replay",
      data_source_id: "ds-1",
      data_source_name: null,
      source_binding_id: "b-1",
      binding_label: null,
      binding_version: null,
      source_endpoint_id: null,
      endpoint_label: null,
      replay_run_id: "run-14",
      replay_run_label: "14",
    },
    record: {
      packet_id: "p-1",
      evidence_id: null,
      packet_definition_id: "pd-1",
      packet_definition_name: "HK",
      packet_definition_version: 2,
      validity_state: null,
    },
  },
});

describe("api D1: the one-sample read", () => {
  it("reads a ready sample with null names, labels and validity", () => {
    const r = decode(sampleReadReader, ready());
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.status).toBe("ready");
    expect(r.value.sample?.engineering_value.state).toBe("limited");
    expect(r.value.sample?.source.binding_label).toBeNull();
  });

  it("reads every non-ready status with no sample", () => {
    for (const status of ["not_found", "ambiguous", "timeout", "unsupported", "unavailable"])
      expect(decode(sampleReadReader, { status, sample: null }).ok, status).toBe(true);
  });

  it("keeps a new word as unrecognized instead of failing the read", () => {
    const body = ready();
    body.status = "throttled";
    body.sample.quality = "questionable";
    body.sample.source.realm = "training";
    const r = decode(sampleReadReader, body);
    if (!r.ok) throw new Error(r.error.message);
    expect(isKnown(r.value.status)).toBe(false);
    expect(r.value.sample && isKnown(r.value.sample.quality)).toBe(false);
  });

  it("refuses a ready sample without a receipt time, naming the path", () => {
    const body = ready();
    const { receipt_time: _gone, ...rest } = body.sample;
    const r = decode(sampleReadReader, { ...body, sample: rest });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.message).toContain("receipt_time");
  });
});

describe("samplePath", () => {
  const ids = decode(d.object({ m: missionId, sc: spacecraftId }), { m: "m-1", sc: "sc-312" });
  if (!ids.ok) throw new Error(ids.error.message);
  const key = { sampleId: "s/1", pointId: pointIdReader("EPS.VBAT"), spacecraftId: ids.value.sc };

  it("passes receipt_time when known, for an exact match", () => {
    const at = "2026-11-08T02:08:11.250Z";
    const url = new URL(
      samplePath(ids.value.m, { ...key, receiptTime: at, at: "2026-11-08T02:08:11Z" }),
      "https://x.test",
    );
    expect(url.pathname).toBe("/missions/m-1/telemetry/samples/s%2F1");
    expect(Object.fromEntries(url.searchParams)).toEqual({
      point_id: pointIdReader("EPS.VBAT"),
      spacecraft_id: "sc-312",
      receipt_time: at,
    });
  });

  it("without receipt_time passes at, so api searches ±60 s rather than a day", () => {
    const at = "2026-11-08T02:08:11Z";
    const path = (k: { receiptTime: null; at: string | null }) =>
      new URL(samplePath(ids.value.m, { ...key, ...k }), "https://x.test").searchParams;
    expect(path({ receiptTime: null, at }).has("receipt_time")).toBe(false);
    expect(path({ receiptTime: null, at }).get("at")).toBe(at);
    expect([...path({ receiptTime: null, at: null }).keys()]).toEqual([
      "point_id",
      "spacecraft_id",
    ]);
  });
});
