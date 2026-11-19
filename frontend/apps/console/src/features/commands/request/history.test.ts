import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { fetchHistory, historyReader } from "./history.ts";

const body = {
  request_id: "cr-1",
  spacecraft_id: "sc-007",
  attempts: [
    {
      attempt_id: "at-2",
      state: "released",
      uncertain: false,
      failure_reason: null,
      contact: { id: "c-1", label: "EARENDIL-007 · PUQ 07:20Z pass" },
      path_id: "p-1",
      transport_binding_id: "tb-1",
      encoded_size_bytes: 12,
      attempted_at: "2026-11-16T03:11:50Z",
      released_at: "2026-11-16T03:11:58Z",
    },
    {
      attempt_id: "at-1",
      state: "release_rerouted",
      uncertain: false,
      failure_reason: "link down",
      contact: null,
      path_id: null,
      transport_binding_id: null,
      encoded_size_bytes: null,
      attempted_at: "2026-11-16T03:02:00Z",
      released_at: null,
    },
  ],
  attempts_next: null,
  verifiers: [
    {
      instance_id: "vi-1",
      attempt_id: "at-2",
      verifier_id: "v-1",
      name: "Mode applied",
      phase: "completion",
      severity: "warning",
      state: "satisfied",
      failure_code: null,
      matched_at: "2026-11-16T03:12:04Z",
      timeout_at: "2026-11-16T03:12:30Z",
      evidence_status: "ready",
      evidence: {
        kind: "telemetry",
        sample_id: "s-1",
        point_id: "HK.sc_mode",
        point_name: "sc_mode",
        packet_id: "pk-1",
        evidence_id: "ev-1",
        quality: "good",
        raw_value_json: "2",
        engineering_value_json: "2",
        received_at: "2026-11-16T03:12:03Z",
        generated_at: null,
      },
    },
    {
      instance_id: "vi-2",
      attempt_id: "at-2",
      verifier_id: "v-2",
      name: null,
      phase: "acceptance",
      severity: null,
      state: "satisfied",
      failure_code: null,
      matched_at: "2026-11-16T03:11:59Z",
      timeout_at: null,
      evidence_status: "ready",
      evidence: {
        kind: "transport",
        source: "capability_record",
        record_id: "r-1",
        action: "uplink_ack",
        signal_phase: null,
        at: "2026-11-16T03:11:59Z",
        recorded_at: "2026-11-16T03:11:59Z",
      },
    },
  ],
  verifiers_next: "vi-2",
};

afterEach(() => vi.unstubAllGlobals());

describe("command request history (U68 R3/R4)", () => {
  it("decodes attempts and verifiers with both evidence kinds; a new state keeps its word", () => {
    const r = decode(historyReader, body);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value.attempts[1]?.state).toEqual({ unrecognized: "release_rerouted" });
    expect(r.value.verifiers.map((v) => v.evidence?.kind)).toEqual(["telemetry", "transport"]);
    expect(r.value.verifiers_next).toBe("vi-2");
  });
  it("pages with the server's cursors", async () => {
    const fetchMock = vi.fn((_url: string) => Promise.resolve(Response.json({ data: body })));
    vi.stubGlobal("fetch", fetchMock);
    await fetchHistory(missionId("m"), "cr-1", { verifiers: "vi-2" });
    expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toContain(
      "/missions/m/command-requests/cr-1/history?verifiers_after=vi-2",
    );
  });
});
