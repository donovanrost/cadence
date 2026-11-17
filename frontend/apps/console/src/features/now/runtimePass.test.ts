import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { attentionReader, type Attention } from "./attention.ts";
import { startEvidence, startKeepsTrying, startReasonAction } from "./contactStart.ts";
import { resolvedWords } from "./resolved.ts";
import { runtimeEvidence } from "./runtime.ts";
import { nextPassLine } from "./runtimePass.ts";

const NOW = new Date("2026-11-17T14:50:00Z");
const base = {
  conflict: null,
  state: "open",
  acknowledged_by: null,
  contact_id: null,
  station: null,
  provider: null,
  starts_at: null,
  raised_at: "2026-11-17T14:40:00Z",
  provider_message: null,
  resolution: null,
};
const read = (o: Record<string, unknown>): Attention => {
  const r = decode(attentionReader, { ...base, ...o });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const pass = (o: Record<string, unknown> = {}) => ({
  contact_id: "contact-1",
  spacecraft_id: "spacecraft-earendil-004",
  spacecraft_name: "EARENDIL-004",
  station: { name: "Svalbard", code: "SVA" },
  starts_at: "2026-11-17T15:10:00Z",
  ends_at: "2026-11-17T15:20:00Z",
  in_progress: false,
  started: false,
  ...o,
});
const runtime = (o: Record<string, unknown> = {}) =>
  read({
    id: "attention:mission_runtime:m",
    source: "mission_runtime",
    conflict: "generation_not_applied",
    reason: "spec_mismatch",
    reason_detail: "binding_set_content_sha256",
    desired_generation: 9,
    applied_generation: null,
    ...o,
  });
const passLine = (o: Record<string, unknown>) =>
  nextPassLine(runtime({ next_pass: pass(o) }).next_pass, NOW);

/** ux U91 (api's admission-alert shape, final): the pass at stake, and who fixes it. */
describe("mission_runtime's next pass (U91)", () => {
  it("not started yet: the next pass, its craft and station code", () => {
    expect(passLine({})).toBe("The next pass starts at 15:10Z: EARENDIL-004, SVA.");
    expect(passLine({ station: { name: "Svalbard", code: null } })).toBe(
      "The next pass starts at 15:10Z: EARENDIL-004, Svalbard.",
    );
    expect(passLine({ spacecraft_name: null })).toBe("The next pass starts at 15:10Z: SVA.");
    expect(passLine({ station: null })).toBe("The next pass starts at 15:10Z: EARENDIL-004.");
    expect(passLine({ spacecraft_name: null, station: null })).toBe(
      "The next pass starts at 15:10Z.",
    );
  });

  it("in its window: started before this keeps its telemetry; not started isn't received", () => {
    expect(passLine({ in_progress: true, started: true })).toBe(
      "EARENDIL-004's SVA pass started before this, so its telemetry is kept and processed once the runtime is back.",
    );
    expect(passLine({ in_progress: true, started: false })).toBe(
      "EARENDIL-004's SVA pass couldn't start, so its telemetry isn't being received.",
    );
    expect(
      passLine({ in_progress: true, started: false, spacecraft_name: null, station: null }),
    ).toBe("The pass couldn't start, so its telemetry isn't being received.");
    expect(passLine({ in_progress: true, started: undefined })).toBe(
      "EARENDIL-004's SVA pass is in progress.",
    );
    expect(nextPassLine(null)).toBeNull();
  });

  it("spec_mismatch with nothing running: verify, tell the team, the telemetry lines, the pass", () => {
    const a = runtime({ next_pass: pass() });
    expect(runtimeEvidence(a, NOW)).toBe(
      "Cadence can't verify this mission's active configuration, so it won't run it. It's a fault in Cadence, not in this mission's setup. Tell the team that runs Cadence for you; nothing in the console fixes it. Until this is fixed, passes can't start, so their telemetry isn't received. Cadence keeps trying to start a pass while its window is open, so it receives telemetry from the moment this is fixed. The next pass starts at 15:10Z: EARENDIL-004, SVA.",
    );
    // reason_detail is opaque: never in the sentence.
    expect(runtimeEvidence(a, NOW)).not.toContain("binding_set");
    // Something still running: no telemetry lines.
    expect(runtimeEvidence(runtime({ applied_generation: 8 }), NOW)).not.toContain(
      "Until this is fixed",
    );
  });

  it("resolves as 'runtime started'", () => {
    expect(
      resolvedWords(
        {
          id: "attention:mission_runtime:m",
          resolved_by: { kind: "system", id: null, name: null },
          action: "applied",
          resolved_at: "2026-11-17T15:00:00Z",
          note: null,
        },
        NOW,
      ),
    ).toBe("Resolved: runtime started.");
  });
});

describe("contact_start no_runtime_spec by reason_detail (U91)", () => {
  const start = (detail: string | null, o: Record<string, unknown> = {}) =>
    read({
      id: "attention:contact_start:c-1",
      source: "contact_start",
      conflict: "not_started",
      reason: "no_runtime_spec",
      reason_detail: detail,
      ...o,
    });

  it("configuration_unverifiable: Cadence's fault, no Open Changes, keeps trying on the detail", () => {
    const a = start("configuration_unverifiable");
    expect(startEvidence(a, NOW)).toBe(
      "Cadence can't verify this mission's active configuration, so this pass can't start. It's a fault in Cadence: tell the team that runs Cadence for you.",
    );
    expect(startReasonAction(a)).toBeNull();
    expect(startKeepsTrying(a)).toBe(
      "Cadence keeps trying while the window is open, so the pass receives telemetry from the moment this is fixed.",
    );
    expect(
      startKeepsTrying(start("configuration_unverifiable", { conflict: "missed" })),
    ).toBeNull();
  });

  it("no_configuration and null keep today's words and Open Changes", () => {
    for (const detail of ["no_configuration", null]) {
      const a = start(detail);
      expect(startEvidence(a, NOW)).toBe(
        "The mission's runtime has no active configuration, so passes can't start.",
      );
      expect(startReasonAction(a)?.label).toBe("Open Changes");
      expect(startKeepsTrying(a)).toBeNull();
    }
  });
});
