import { describe, expect, it } from "vite-plus/test";
import { groupOf } from "./fixtures.ts";
import { needsYouCards } from "./needsYou.ts";
import { notPlottable, plotSentence, pointName, type VerifierSeries } from "./series.ts";

const member = (stage: string, position = 0, end_reason: string | null = null) => ({
  target_index: 0,
  command_id: "cmd-1",
  verify_by: null,
  occurred_at: null,
  request_id: `req-${position}`,
  command_name: position === 0 ? "SET_MODE" : "PING",
  position,
  stage,
  end_reason,
});
const target = (id: string, stage: string, extra: Record<string, unknown> = {}) => ({
  scid: 7,
  last_event_at: null,
  blocked: null,
  withdrawn_after_go: null,
  spacecraft_id: id,
  name: id.toUpperCase(),
  stage,
  members: [member(stage)],
  ...extra,
});
const series = (samples: { t: string; value_json: string | null }[]): VerifierSeries => ({
  telemetry: undefined,
  points: undefined,
  verifier: { position: 0, command_id: "c", command_name: "SET_MODE" },
  point: { id: "THERM.sp", name: "batt_setpoint", unit: "°C", type: "numeric" },
  reason: null,
  commanded: { value_json: "8.0", comparison: "equal" },
  band: null,
  window: { from: "2026-11-12T00:05:00Z", to: "2026-11-12T00:06:00Z" },
  targets: [
    {
      spacecraft_id: "a",
      name: "A",
      verifier_state: "failed",
      verifier: undefined,
      timeout_at: undefined,
      matched_at: undefined,
      samples,
    },
  ],
  target_count: 1,
  truncated: false,
  summary: { met: 0, not_met: 1, pending: 0 },
});

describe("N Needs you cards", () => {
  it("says what the verifier point last read against what was commanded", () => {
    const g = groupOf({
      state: "queued",
      targets: [
        target("a", "verify_failed", {
          members: [
            { ...member("verify_failed"), failure_reason: "verify_failed" },
            member("canceled", 1, "earlier_command_failed"),
          ],
        }),
      ],
    });
    const [c] = needsYouCards(
      g,
      g.targets,
      series([{ t: "2026-11-12T00:05:40Z", value_json: "5" }]),
    );
    expect([c?.tag, c?.explanation, c?.resend]).toEqual([
      "Verify failed",
      "SET_MODE was sent, but batt_setpoint last read 5 °C at 00:05Z; it was commanded to 8 °C. 1 later uplink to it was stopped.",
      true,
    ]);
    // Live (qa #65): timed out with no samples and an untyped, unnamed point. #795: the member's
    // own failure_reason says it timed out (its member_failed event may be pages back).
    const bare = series([]);
    const live = { ...bare, point: { id: "p", name: "p", unit: null, type: null } };
    const timedOut = groupOf({
      state: "queued",
      targets: [
        target("a", "verify_failed", {
          members: [{ ...member("verify_failed"), failure_reason: "verify_timed_out" }],
        }),
      ],
    });
    expect(needsYouCards(timedOut, timedOut.targets, live)[0]?.explanation).toBe(
      "SET_MODE was sent, but no reading of the verifier point arrived before verification timed out.",
    );
    expect(needsYouCards(timedOut, timedOut.targets, null)[0]?.explanation).toBe(
      "SET_MODE was sent, but verification timed out.",
    );
    expect([pointName(live), notPlottable(live)]).toEqual([
      "the verifier point",
      "No readings of the verifier point in the verify window",
    ]);
  });

  it("names no-ACK and release failures, and a held lane without Re-send", () => {
    const g = groupOf({
      state: "queued",
      targets: [
        target("a", "indeterminate"),
        target("b", "release_failed"),
        target("c", "queued_for_contact", {
          blocked: { reason: "lane_release_uncertain", command_request_id: "r" },
        }),
        target("d", "verified"),
      ],
    });
    expect(
      needsYouCards(g, g.targets, null).map((c) => [c.target.spacecraft_id, c.tag, c.resend]),
    ).toEqual([
      ["a", "Outcome unclear", true],
      ["b", "Release failed", true],
      ["c", "Lane held", false],
    ]);
    expect(needsYouCards(g, g.targets, null)[0]?.explanation).toBe(
      "No ACK for SET_MODE: Cadence can't tell whether it arrived. Check the spacecraft before re-sending.",
    );
  });
});

describe("a verifier plot's sentence (a11y checklist C)", () => {
  const t = (id: string) => ({
    spacecraft_id: id,
    name: `EARENDIL-${id}`,
    verifier_state: "satisfied" as const,
    verifier: undefined,
    timeout_at: undefined,
    matched_at: undefined,
    samples: [],
  });
  it("names the point, up to three targets, and how they came out", () => {
    const one = series([]);
    expect(plotSentence(one)).toBe("batt_setpoint for A: 1 not met.");
    const many = {
      ...one,
      targets: ["001", "002", "003", "004", "005"].map(t),
      target_count: 5,
      summary: { met: 4, not_met: 1, pending: 0 },
    };
    expect(plotSentence(many)).toBe(
      "batt_setpoint for EARENDIL-001, EARENDIL-002, EARENDIL-003 and 2 more: 4 met, 1 not met.",
    );
    expect(plotSentence({ ...many, targets: many.targets.slice(0, 2), target_count: 2 })).toBe(
      "batt_setpoint for EARENDIL-001 and EARENDIL-002: 4 met, 1 not met.",
    );
  });
});
