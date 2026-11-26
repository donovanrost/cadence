import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { historyReader, type Attempt, type HistoryVerifier } from "./history.ts";
import { attemptLine, evidenceLine, technicalLines, verifierLine } from "./historyWords.ts";

const attempt = (o: Record<string, unknown> = {}): Attempt => {
  const r = decode(historyReader, {
    request_id: "cr",
    spacecraft_id: "sc",
    attempts: [
      {
        attempt_id: "at-1",
        state: "released",
        uncertain: false,
        failure_reason: null,
        contact: { id: "c", label: "EARENDIL-007 · PUQ 07:20Z pass" },
        path_id: null,
        transport_binding_id: null,
        encoded_size_bytes: 12,
        attempted_at: "2026-11-16T03:11:50Z",
        released_at: "2026-11-16T03:11:58Z",
        ...o,
      },
    ],
    attempts_next: null,
    verifiers: [],
    verifiers_next: null,
  });
  if (!r.ok || !r.value.attempts[0]) throw new Error("fixture");
  return r.value.attempts[0];
};
const verifier = (o: Record<string, unknown> = {}): HistoryVerifier => {
  const r = decode(historyReader, {
    request_id: "cr",
    spacecraft_id: "sc",
    attempts: [],
    attempts_next: null,
    verifiers: [
      {
        instance_id: "vi",
        attempt_id: "at-1",
        verifier_id: "v-1",
        name: "Mode applied",
        phase: "completion",
        severity: null,
        state: "satisfied",
        failure_code: null,
        matched_at: "2026-11-16T03:12:04Z",
        timeout_at: "2026-11-16T03:12:30Z",
        evidence_status: "ready",
        evidence: {
          kind: "telemetry",
          sample_id: "s",
          point_id: "HK.sc_mode",
          point_name: null,
          packet_id: null,
          evidence_id: null,
          quality: "good",
          raw_value_json: "2",
          engineering_value_json: "2",
          received_at: "2026-11-16T03:12:03Z",
          generated_at: null,
        },
        ...o,
      },
    ],
    verifiers_next: null,
  });
  if (!r.ok || !r.value.verifiers[0]) throw new Error("fixture");
  return r.value.verifiers[0];
};

describe("history words (ux U70)", () => {
  it("words attempts: released, refused, uncertain (timeout), resolved", () => {
    expect(attemptLine(attempt(), "EARENDIL-007")).toBe(
      "Released at 03:11:58Z during EARENDIL-007 · PUQ 07:20Z pass · 12 bytes",
    );
    const refused = attempt({
      state: "release_failed",
      released_at: null,
      failure_reason: "refused: {:earlier_command_failed, …}",
      failure: { kind: "refused", code: "earlier_command_failed" },
    });
    expect(attemptLine(refused, "EARENDIL-007")).toBe(
      "Release failed at 03:11:50Z: an earlier uplink in it failed",
    );
    expect(technicalLines([refused], [])[0]).toContain("refused: {:earlier_command_failed, …}");
    expect(
      attemptLine(
        attempt({ state: "release_uncertain", failure: { kind: "uncertain", code: "timeout" } }),
        null,
      ),
    ).toBe(
      "Outcome unclear at 03:11:50Z: the send didn't answer in time, so Cadence can't tell whether it went",
    );
    expect(
      attemptLine(
        attempt({
          state: "release_failed",
          failure: {
            kind: "resolved",
            code: "not_sent",
            by: { id: "u", name: "Mira K." },
            at: "2026-11-16T03:20:05Z",
          },
        }),
        null,
      ),
    ).toBe("Resolved as not sent by Mira K. at 03:20:05Z");
    expect(
      attemptLine(
        attempt({ state: "release_failed", failure: { kind: "resolved", code: "rejected" } }),
        null,
      ),
    ).toBe("Resolved as rejected; who resolved it wasn't recorded");
    expect(
      attemptLine(
        attempt({
          state: "release_failed",
          failure: {
            kind: "resolved",
            code: "not_sent",
            by: { id: "key-1", name: "Ground ops key", kind: "service_identity" },
            at: "2026-11-16T03:20:05Z",
          },
        }),
        null,
      ),
    ).toBe("Resolved as not sent by Ground ops key (a service identity) at 03:20:05Z");
  });
  it("marks a service identity resolver, named or not (ux U70, U103)", () => {
    const resolved = (
      by:
        | { id: string; name: string | null; kind?: "user" | "service_identity" }
        | null
        | undefined,
    ) =>
      attemptLine(
        attempt({
          state: "release_failed",
          failure: { kind: "resolved", code: "not_sent", by, at: "2026-11-16T03:20:05Z" },
        }),
        null,
      );
    // A person: unchanged, with or without the kind.
    expect(resolved({ id: "u", name: "Mira K.", kind: "user" })).toBe(
      "Resolved as not sent by Mira K. at 03:20:05Z",
    );
    // A named service identity: its name, marked as a service.
    expect(resolved({ id: "key-1", name: "ops-automation", kind: "service_identity" })).toBe(
      "Resolved as not sent by ops-automation (a service identity) at 03:20:05Z",
    );
    // A nameless service identity: the kind is known, so it's said; never the id.
    expect(resolved({ id: "key-1", name: null, kind: "service_identity" })).toBe(
      "Resolved as not sent by a service identity at 03:20:05Z",
    );
    // A resolver with no name and no known kind: who isn't known.
    expect(resolved({ id: "u", name: null })).toBe(
      "Resolved as not sent at 03:20:05Z; who resolved it isn't known",
    );
    expect(resolved({ id: "u", name: null, kind: "user" })).toBe(
      "Resolved as not sent at 03:20:05Z; who resolved it isn't known",
    );
    // No resolver recorded.
    expect(resolved(undefined)).toBe(
      "Resolved as not sent at 03:20:05Z; who resolved it wasn't recorded",
    );
    expect(resolved(null)).toBe(
      "Resolved as not sent at 03:20:05Z; who resolved it wasn't recorded",
    );
  });
  it("puts a nameless resolver's id in Technical details (ux U70, U25)", () => {
    const resolved = (
      by: { id: string; name: string | null; kind?: "user" | "service_identity" } | null,
    ) =>
      technicalLines(
        [
          attempt({
            state: "release_failed",
            failure: { kind: "resolved", code: "not_sent", by, at: "2026-11-16T03:20:05Z" },
          }),
        ],
        [],
      )[0];
    expect(resolved({ id: "key-1", name: null, kind: "service_identity" })).toBe(
      "Attempt at-1 · resolved by service identity key-1",
    );
    expect(resolved({ id: "u-7", name: null })).toBe("Attempt at-1 · resolved by u-7");
    // Named, the line already says who: no id.
    expect(resolved({ id: "key-1", name: "ops-automation", kind: "service_identity" })).toBe(
      "Attempt at-1",
    );
    expect(resolved(null)).toBe("Attempt at-1");
  });
  it("words verifiers and their evidence", () => {
    expect(verifierLine(verifier())).toBe("Mode applied · verified at 03:12:04Z");
    expect(evidenceLine(verifier())).toEqual({
      text: "HK.sc_mode = 2, received 03:12:03Z",
      caution: null,
    });
    const timed = verifier({
      state: "timed_out",
      matched_at: null,
      evidence_status: "unmatched",
      evidence: null,
    });
    expect(verifierLine(timed)).toBe(
      "Mode applied · timed out at 03:12:30Z: no matching telemetry",
    );
    expect(verifierLine(verifier({ state: "pending", matched_at: null }))).toBe(
      "Mode applied · verify by 03:12:30Z",
    );
    const differs = verifier({
      evidence: {
        kind: "telemetry",
        sample_id: "s",
        point_id: "TH.temp",
        point_name: null,
        packet_id: null,
        evidence_id: null,
        quality: "suspect",
        raw_value_json: "412",
        engineering_value_json: "8.0",
        unit: "°C",
        received_at: "2026-11-16T03:12:03Z",
        generated_at: null,
      },
    });
    expect(evidenceLine(differs)).toEqual({
      text: "TH.temp = 8.0 °C (raw 412), received 03:12:03Z",
      caution: "quality: suspect",
    });
    const transport = verifier({
      evidence: {
        kind: "transport",
        source: "action_request",
        record_id: "r",
        action: "uplink_request",
        signal_phase: "failure",
        at: "2026-11-16T03:11:58Z",
        recorded_at: null,
      },
    });
    expect(evidenceLine(transport)).toEqual({
      text: "Uplink request failed at 03:11:58Z",
      caution: null,
      crit: true,
    });
    expect(evidenceLine(verifier({ evidence_status: "unavailable", evidence: null }))?.text).toBe(
      "The matching record is no longer available.",
    );
  });
});
