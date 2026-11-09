import { logLines } from "./eventLog.ts";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { formatLimitLike, formatValue, type Alarm } from "@/features/alarms/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { historyReader, type LimitIntervals } from "./api.ts";
import {
  formatRate,
  heroStatus,
  limitSegments,
  neighbours,
  pickAlarm,
  ratePerHour,
  sisters,
  trendSentence,
} from "./model.ts";

const thresholds = { red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 };

function alarmRow(id: string, spacecraftId: string, overrides: Partial<Alarm> = {}): Alarm {
  return {
    id,
    spacecraft_id: spacecraftId,
    point: { id: "EPS.VBAT", name: "VBAT", subsystem: "EPS", unit: "V", description: null },
    severity: "critical",
    active: true,
    condition: "red_low",
    value: 23.1,
    limit_set_name: "DEFAULT",
    thresholds,
    first_crossed_at: "2026-11-08T02:35:02Z",
    generation_time: "2026-11-08T02:41:14Z",
    received_at: "2026-11-08T02:41:15Z",
    ...overrides,
  };
}

const hour = 3_600_000;
const window = { from: 0, to: 6 * hour };

describe("limitSegments", () => {
  it("falls back to the alarm's thresholds across the window", () => {
    const segments = limitSegments(null, window, thresholds);
    expect(segments).toHaveLength(4);
    expect(segments.every((s) => s.from === 0 && s.to === 6 * hour)).toBe(true);
  });

  it("clips definition intervals to the window and follows band changes", () => {
    const iso = (t: number) => new Date(t).toISOString();
    const interval = (from: number, to: number | null, redLow: number) => ({
      from: iso(from),
      to: to === null ? null : iso(to),
      limit_set_name: "DEFAULT",
      limit_definition_id: "def",
      limit_definition_version: 1,
      scope: { type: "mission", ref: null },
      thresholds: { red_low: redLow, yellow_low: null, yellow_high: null, red_high: null },
    });
    const intervals: LimitIntervals = {
      point_id: "EPS.VBAT",
      spacecraft_id: null,
      from: iso(0),
      to: iso(6 * hour),
      intervals: [interval(-hour, 2 * hour, 24), interval(2 * hour, null, 24.5)],
    };
    const segments = limitSegments(intervals, window, null);
    expect(segments.map((s) => [s.from, s.to, s.value])).toEqual([
      [0, 2 * hour, 24],
      [2 * hour, 6 * hour, 24.5],
    ]);
  });
});

describe("history decoding", () => {
  const body = (buckets: unknown[]) => ({
    point_id: "EPS.VBAT",
    unit: "V",
    description: null,
    spacecraft_id: "sc",
    from: "2026-11-08T00:00:00Z",
    to: "2026-11-08T01:00:00Z",
    bucket_width_ms: 7200,
    truncated: false,
    buckets,
  });
  const b = (t: string, min: number, mean: number, max: number) => ({
    t,
    t_end: t,
    min,
    mean,
    max,
    count: 1,
  });

  it("accepts ordered, consistent buckets", () => {
    expect(decode(historyReader, body([b("2026-11-08T00:00:00Z", 1, 2, 3)])).ok).toBe(true);
  });

  it("rejects a mean outside min..max and out-of-order buckets", () => {
    expect(decode(historyReader, body([b("2026-11-08T00:00:00Z", 1, 5, 3)])).ok).toBe(false);
    expect(
      decode(
        historyReader,
        body([b("2026-11-08T00:10:00Z", 1, 2, 3), b("2026-11-08T00:00:00Z", 1, 2, 3)]),
      ).ok,
    ).toBe(false);
  });
});

describe("investigate model", () => {
  it("picks the alarm named in the URL, else the first active", () => {
    const alarms = [alarmRow("a", "sc1"), alarmRow("b", "sc1")];
    expect(pickAlarm(alarms, "b")?.id).toBe("b");
    expect(pickAlarm(alarms, "missing")?.id).toBe("a");
    expect(pickAlarm([], null)).toBeNull();
  });

  it("computes the rate per hour from first and last means", () => {
    const p = (t: number, mean: number) => ({ t, min: mean, mean, max: mean });
    expect(ratePerHour([p(0, 25), p(2 * hour, 24)])).toBeCloseTo(-0.5);
    expect(ratePerHour([p(0, 25)])).toBeNull();
    expect(ratePerHour([p(0, 25), p(60_000, 30)])).toBeNull();
    // qa #8: a run before a gap doesn't count; 2 min after the gap is too short for a rate.
    expect(ratePerHour([p(0, 0), p(26 * 60_000, 5), p(28 * 60_000, 6)], 60_000)).toBeNull();
    // 15-min buckets: the 30-min gap splits; the last run (30..50 min) gives (7 − 5) / 20 min.
    expect(
      ratePerHour([p(0, 0), p(30 * 60_000, 5), p(31 * 60_000, 5), p(50 * 60_000, 7)], 15 * 60_000),
    ).toBeCloseTo(6);
  });

  it("describes the trend and a red crossing in words", () => {
    const p = (t: number, mean: number) => ({ t, min: mean, mean, max: mean });
    const sentence = trendSentence(
      "VBAT",
      "6H",
      [p(0, 26.8), p(hour, 23.4)],
      limitSegments(null, window, thresholds),
    );
    expect(sentence).toBe(
      "VBAT over 6H, falling from 26.8 to 23.4, range 23.4 to 26.8, crossing the 24 red limit.",
    );
  });

  it("steps through the plane by slot", () => {
    const fleet = [spacecraftRow(1), spacecraftRow(2), spacecraftRow(3), spacecraftRow(26)];
    const at = (scid: number) => fleet.find((sc) => sc.scid === scid) ?? spacecraftRow(scid);
    const { prev, next } = neighbours(fleet, at(2));
    expect([prev?.scid, next?.scid]).toEqual([1, 3]);
    expect(neighbours(fleet, at(3)).next).toBeNull();
  });

  it("finds sisters: same plane, same point, active", () => {
    const fleet = [spacecraftRow(1), spacecraftRow(2), spacecraftRow(3), spacecraftRow(26)];
    const me = fleet[0] ?? spacecraftRow(1);
    const alarms = [
      alarmRow("a", me.id),
      alarmRow("b", "spacecraft-earendil-002"),
      alarmRow("c", "spacecraft-earendil-003", {
        point: { id: "EPS.OTHER", name: "X", subsystem: null, unit: "V", description: null },
      }),
      alarmRow("d", "spacecraft-earendil-026"),
    ];
    expect(sisters(alarms, fleet, me, "EPS.VBAT").map((s) => s.sc.scid)).toEqual([2]);
  });

  it("formats values without inventing precision", () => {
    expect(formatValue(23.1234)).toBe("23.1");
    expect(formatValue(-0.4)).toBe("−0.4");
    expect(formatValue(4812)).toBe("4,812");
    expect(formatValue("SAFE")).toBe("SAFE");
    expect(formatLimitLike(24, 23.1)).toBe("24.0");
    expect(formatLimitLike(-5.5, -6.12)).toBe("−5.50");
    expect(formatLimitLike(24.25, 23)).toBe("24.3");
    expect(formatLimitLike(null, 23.1)).toBeNull();
  });
});

describe("hero status (ux review fix 1)", () => {
  it("lets the worst active alarm outrank the fleet state, even never_heard", () => {
    const sc = spacecraftRow(1, { state: "never_heard", last_received_at: null });
    expect(
      heroStatus(sc, [alarmRow("a", sc.id, { severity: "caution" }), alarmRow("b", sc.id)]),
    ).toEqual({
      state: "crit",
      label: "Critical · EPS",
    });
  });

  it("falls back to the fleet state without alarms", () => {
    expect(heroStatus(spacecraftRow(1), [])).toEqual({ state: "nominal", label: "Nominal" });
  });

  it("formats a rate with two decimals and a real minus", () => {
    expect(formatRate(-0.4271)).toBe("−0.43");
    expect(formatRate(0.5)).toBe("+0.50");
  });
});

describe("event log lines (B2)", () => {
  const mission = {
    id: "m1",
    at: "2026-11-08T02:08:11Z",
    kind: "limit" as const,
    raw_kind: "limit_violation",
    severity: "critical" as const,
    text: "VBAT crossed red low",
    detail: null,
    spacecraft: null,
    refs: {
      alarm_id: null,
      point_id: "EPS.VBAT",
      command_request_id: null,
      contact_id: null,
      subject: null,
    },
  };
  const raised = {
    id: "e1",
    kind: "raised" as const,
    actor: null,
    at: "2026-11-08T02:08:11Z",
    payload: {},
  };
  const acked = {
    id: "e2",
    kind: "acknowledged" as const,
    actor: { kind: "user", id: "u", name: "Mira K." },
    at: "2026-11-08T02:10:00Z",
    payload: {},
  };

  it("merges lifecycle actions into mission events, newest first, without duplicates", () => {
    expect(logLines([mission], [raised, acked]).map((l) => l.text)).toEqual([
      "Acknowledged by Mira K.",
      "VBAT crossed red low",
    ]);
  });

  it("falls back to the whole episode history without the mission read", () => {
    expect(logLines(null, [raised, acked])).toHaveLength(2);
  });
});
