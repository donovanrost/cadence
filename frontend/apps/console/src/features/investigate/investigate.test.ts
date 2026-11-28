import { logLines, type LogEpisode } from "./eventLog.ts";
import { mergeSamples, tailPoints } from "./tail.ts";
import {
  conditionLine,
  howItEnded,
  occurrenceReader,
  occurrenceSummary,
  peakFrom,
  type Occurrence,
} from "./history/api.ts";
import { argsSummary, evidenceWords, releaseRule } from "./uplink/api.ts";
import { byDay, bytesWords, causeWithOwner, rebooked, recentTag, ruleWords } from "./passes/api.ts";
import { catalogCaution, jsonWords, protocolLine, routingWords } from "./configuration/api.ts";
import { filterCounts, pointMark, pointsFrom, toCsv, visiblePoints } from "./telemetry/model.ts";
import { pointLimits } from "@/features/telemetry/index.ts";
import { describe, expect, it } from "vite-plus/test";
import {
  spacecraftId as spacecraftIdReader,
  decode,
  pointId as pointIdReader,
} from "@/api/index.ts";
import { formatLimitLike, formatValue, type Alarm } from "@/features/alarms/index.ts";
import { spacecraftRow, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { aosShort, ringDots, sparkPoints } from "./sisters.ts";
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
  lastCleared,
  MAX_AUTO_PAGES,
  wantsMorePages,
} from "./model.ts";

const thresholds = { red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 };

function alarmRow(id: string, spacecraftId: string, overrides: Partial<Alarm> = {}): Alarm {
  return {
    id,
    spacecraft_id: spacecraftIdReader(spacecraftId),
    point: {
      id: pointIdReader("EPS.VBAT"),
      name: "VBAT",
      subsystem: "EPS",
      unit: "V",
      description: null,
    },
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
      scope: { type: "mission" as const, ref: null },
      thresholds: { red_low: redLow, yellow_low: null, yellow_high: null, red_high: null },
    });
    const intervals: LimitIntervals = {
      point_id: pointIdReader("EPS.VBAT"),
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
    point_id: pointIdReader("EPS.VBAT"),
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

describe("a deep-linked alarm on a later page (#827)", () => {
  const loaded = [alarmRow("a", "sc1"), alarmRow("b", "sc1")];
  const none = { alarm: null, point: null };

  it("loads another page while the asked-for alarm is not among those loaded", () => {
    expect(wantsMorePages(loaded, "c2", { alarm: "far", point: null }, 0)).toBe(true);
    expect(wantsMorePages(loaded, "c2", { alarm: "b", point: null }, 0)).toBe(false);
  });

  it("for a point, loads while no alarm on it is loaded", () => {
    const pointId = loaded[0]?.point.id ?? "";
    expect(wantsMorePages(loaded, "c2", { alarm: null, point: "other" }, 0)).toBe(true);
    expect(wantsMorePages(loaded, "c2", { alarm: null, point: pointId }, 0)).toBe(false);
  });

  it("asks for nothing without a link or without a next page", () => {
    expect(wantsMorePages(loaded, "c2", none, 0)).toBe(false);
    expect(wantsMorePages(loaded, null, { alarm: "far", point: null }, 0)).toBe(false);
  });

  it("is bounded: an id that does not exist cannot page through the whole list", () => {
    const link = { alarm: "missing", point: null };
    expect(wantsMorePages(loaded, "c2", link, MAX_AUTO_PAGES - 1)).toBe(true);
    expect(wantsMorePages(loaded, "c2", link, MAX_AUTO_PAGES)).toBe(false);
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
        point: {
          id: pointIdReader("EPS.OTHER"),
          name: "X",
          subsystem: null,
          unit: "V",
          description: null,
        },
      }),
      alarmRow("d", "spacecraft-earendil-026"),
    ];
    expect(sisters(alarms, fleet, me, pointIdReader("EPS.VBAT")).map((s) => s.sc.scid)).toEqual([
      2,
    ]);
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
      point_id: pointIdReader("EPS.VBAT"),
      command_request_id: null,
      contact_id: null,
      subject: null,
    },
    record: null,
  };
  const raised = {
    id: "e1",
    kind: "raised" as const,
    actor: null,
    at: "2026-11-08T02:08:11Z",
    sample: undefined,
    payload: {},
  };
  const acked = {
    id: "e2",
    kind: "acknowledged" as const,
    actor: { kind: "user" as const, id: "u", name: "Mira K." },
    at: "2026-11-08T02:10:00Z",
    sample: undefined,
    payload: {},
  };

  const epi = (events: LogEpisode["events"]): LogEpisode => ({
    pointId: pointIdReader("EPS.VBAT"),
    openedAt: "2026-11-08T02:00:00Z",
    clearedAt: null,
    events,
  });

  it("merges lifecycle actions into mission events, newest first, without duplicates", () => {
    expect(logLines([mission], epi([raised, acked])).map((l) => l.text)).toEqual([
      "Acknowledged by Mira K.",
      "VBAT crossed red low",
    ]);
  });

  it("falls back to the whole episode history without the mission read", () => {
    expect(logLines(null, epi([raised, acked]))).toHaveLength(2);
  });
});

describe("M8 live tail", () => {
  const s = (t: string, v: string | null, p = "p1") => ({
    point_id: pointIdReader(p),
    value_json: v,
    generation_time: t,
    received_at: null,
    limit_state: null,
  });
  it("merges pushes by generation time, so a backfill lands in place", () => {
    const a = mergeSamples(new Map(), [
      s("2026-11-10T01:00:02Z", "2"),
      s("2026-11-10T01:00:01Z", "1"),
    ]);
    const b = mergeSamples(a, [s("2026-11-10T01:00:01.5Z", "1.5")]);
    expect(b.get("p1")?.map((x) => x.value_json)).toEqual(["1", "1.5", "2"]);
  });
  it("plots numeric samples after the history's last bucket only", () => {
    const after = Date.parse("2026-11-10T01:00:01Z");
    const pts = tailPoints(
      [
        s("2026-11-10T01:00:00Z", "0"),
        s("2026-11-10T01:00:02Z", "2"),
        s("2026-11-10T01:00:03Z", '"SAFE"'),
      ],
      after,
    );
    expect(pts).toEqual([{ t: Date.parse("2026-11-10T01:00:02Z"), min: 2, mean: 2, max: 2 }]);
  });
});

describe("History tab (Investigate.md §History, api's episode reads)", () => {
  const occ = (over: Partial<Occurrence> = {}): Occurrence => ({
    id: "e1",
    source: "ground_limit",
    status: "cleared",
    severity: "critical",
    peak_severity: "critical",
    condition: "red_low",
    direction: "low",
    point: { id: pointIdReader("EPS.VBAT"), name: "VBAT", unit: "V" },
    opened_at: "2026-11-09T03:00:00Z",
    cleared_at: "2026-11-09T04:00:00Z",
    duration_s: 3600,
    ended: "back_in_limits",
    cleared_unacknowledged: false,
    acknowledged_by: null,
    first_value: 23.5,
    last_value: 24.2,
    trigger: undefined,
    ...over,
  });
  it("words the condition and how it ended", () => {
    expect(conditionLine(occ())).toBe("VBAT below red limit");
    expect(howItEnded(occ())).toBe("Back in limits");
    expect(howItEnded(occ({ ended: "source_stopped" }))).toBe("Source stopped reporting it");
    expect(howItEnded(occ({ ended: null, cleared_at: null }))).toBe("Still open");
    // #451 T3b: a monitoring change set retired the alarm's policy while it was open.
    expect(howItEnded(occ({ ended: "rule_retired" }))).toBe("Its rule was retired");
    expect(howItEnded(occ({ ended: "unrecognized" }))).toBe("Ended");
    // The wire value decodes; a way of ending this console doesn't know never fails the read.
    const ended = (v: string) => {
      const r = decode(occurrenceReader, { ...occ(), ended: v });
      return r.ok ? r.value.ended : r.error;
    };
    expect([ended("rule_retired"), ended("rule_reset")]).toEqual(["rule_retired", "unrecognized"]);
  });
  it("takes PEAK from the chart buckets inside the span, by direction; none for catalog", () => {
    const t = (iso: string) => Date.parse(iso);
    const buckets = [
      { t: t("2026-11-09T02:30:00Z"), min: 20, max: 30 },
      { t: t("2026-11-09T03:10:00Z"), min: 22.1, max: 24 },
      { t: t("2026-11-09T03:40:00Z"), min: 22.6, max: 25 },
    ];
    expect(peakFrom(occ(), buckets, 0)).toEqual({ value: 22.1, t: t("2026-11-09T03:10:00Z") });
    expect(peakFrom(occ({ direction: "high" }), buckets, 0)?.value).toBe(25);
    expect(peakFrom(occ({ direction: null }), buckets, 0)).toBeNull();
  });
  it("summarises counts including this episode", () => {
    const h = {
      counts: { d7: 1, d30: 4, d90: 9 },
      median_duration_s: 2280,
      first_opened_at: null,
      retention_days: null,
      items: [],
      next_before: null,
    };
    expect(occurrenceSummary(h)).toBe("4th time in 30 days · median 38m");
    expect(occurrenceSummary({ ...h, counts: { d7: 1, d30: 1, d90: 1 } })).toBe(
      "First time in 30 days · median 38m",
    );
  });
});

describe("Uplink tab words (aa1f493e)", () => {
  const now = new Date("2026-11-10T01:00:00Z");
  it("release rule, evidence, route meta and args", () => {
    const q = {
      position: 1,
      request_id: "r",
      command_id: "c",
      command_name: "SET_MODE",
      arguments_json: '{"mode":3}',
      group: null,
      not_before: null,
      expires_at: "2026-11-10T04:00:00Z",
      queued_at: "2026-11-10T00:00:00Z",
    };
    expect(releaseRule(q, now)).toBe("At next AOS · expires 04:00Z");
    expect(releaseRule({ ...q, not_before: "2026-11-11T03:00:00Z", expires_at: null }, now)).toBe(
      "Not before 11-11 03:00Z",
    );
    expect(argsSummary('{"mode":3}')).toBe("mode 3");
    const p = {
      reservation_id: "p",
      contact_id: null,
      station: { ref: null, id: null, code: "KIR", name: null },
      starts_at: "2026-11-10T02:31:00Z",
      ends_at: "2026-11-10T02:39:00Z",
      uplink_evidence: "attested" as const,
      uplink_confirmed: false,
      attested_by: null,
      provider: undefined,
    };
    expect(evidenceWords(p)).toEqual({ text: "Attested · uplink unconfirmed", caution: true });
    expect(evidenceWords({ ...p, uplink_evidence: "booked", uplink_confirmed: true }).text).toBe(
      "Booked",
    );
  });
});

describe("Passes tab words (api 324428aa)", () => {
  it("rule, day groups and bytes", () => {
    expect(ruleWords({ state: "met", have: 3, need: 3, rules: [] })).toEqual({
      text: "3 of 3 contacts today · rule met",
      caution: false,
    });
    expect(ruleWords({ state: "short", have: 2, need: 3, rules: [] })?.caution).toBe(true);
    expect(ruleWords({ state: "none", have: 0, need: 0, rules: [] })).toBeNull();
    const row = (id: string, at: string) => ({
      id,
      station: null,
      planned_aos: at,
      planned_los: at,
      actual_aos: null,
      actual_los: null,
      received_bytes: null,
      outcome: "realized" as const,
      cause: null,
      owner: null,
    });
    expect(
      byDay([
        row("a", "2026-11-09T01:00:00Z"),
        row("b", "2026-11-10T02:00:00Z"),
        row("c", "2026-11-10T05:00:00Z"),
      ]).map((g) => [g.day, g.rows.map((r) => r.id)]),
    ).toEqual([
      ["2026-11-10", ["c", "b"]],
      ["2026-11-09", ["a"]],
    ]);
    const twice = [row("m", "2026-11-10T18:57:00Z"), row("p", "2026-11-10T18:57:00Z")];
    expect(twice.map((r) => rebooked(twice, r))).toEqual([false, true]);
    // ux #7: the rejected booking of a window that flew elsewhere is off 'Rejected', not Missed.
    const at = "2026-11-10T18:57:00Z";
    const rejected = { ...row("m", at), outcome: "missed" as const };
    const flown = { ...row("p", at), actual_aos: at, outcome: "partial" as const };
    expect(recentTag([rejected, flown], rejected)).toEqual({ state: "off", label: "Rejected" });
    expect(recentTag([rejected], rejected)).toEqual({ state: "crit", label: "Missed" });
    expect(recentTag([rejected, flown], flown).label).toBe("Partial");
    // ux #8: no "(provider)" after a cause that already names the provider.
    expect(causeWithOwner("provider_rejected", "provider")).toBe("Provider rejected");
    expect(causeWithOwner("not_ingested", "us")).toBe("Delivered, not ingested (us)");
    expect(bytesWords(1_234_567)).toBe("1.2 MB");
    expect(bytesWords(null)).toBe("—");
  });
});

describe("Configuration tab words (api-ops 8d8f5c83)", () => {
  it("values, catalog drift and routing", () => {
    expect(jsonWords("892", "bytes")).toBe("892 bytes");
    expect(jsonWords('"SAFE"', null)).toBe("SAFE");
    expect(jsonWords(null, "bytes")).toBe("not set");
    expect(
      catalogCaution({
        running: { id: "a", revision_number: 14 },
        profile: { id: "b", revision_number: 15 },
      }),
    ).toBe("Running rev 14; the profile is on rev 15.");
    expect(
      catalogCaution({
        running: { id: "a", revision_number: 15 },
        profile: { id: "b", revision_number: 15 },
      }),
    ).toBeNull();
    expect(
      routingWords({
        id: "r",
        name: "Primary downlink",
        purpose: "TM",
        direction: "inbound",
        role: "primary",
        enabled: true,
        active: true,
        transport: { id: "t", name: "Svalbard X-band" },
        station: { id: "s", code: "SVB", name: "Svalbard" },
      }),
    ).toBe("SVB · Primary downlink");
  });
});

describe("Telemetry tab (Investigate.md §Telemetry)", () => {
  const pt = (
    id: string,
    state: "nominal" | "caution" | "critical" | "no_data" | null,
    subsystem = "EPS",
    hasLimits?: boolean,
  ) => ({
    id: pointIdReader(id),
    name: id.toLowerCase(),
    description: null,
    unit: null,
    subsystem,
    type: "numeric" as const,
    has_limits: hasLimits,
    latest:
      state === null
        ? null
        : {
            value: 1,
            received_at: null,
            limit_state: state,
            source: undefined,
          },
  });
  it("filters, sorts out-of-limits first, caps pins at 3", () => {
    const ps = [pt("A", "nominal"), pt("B", "critical"), pt("C", null), pt("D", "caution")];
    expect(visiblePoints(ps, "all", "").map((p) => p.id)).toEqual(["B", "D", "A", "C"]);
    expect(visiblePoints(ps, "out", "").map((p) => p.id)).toEqual(["B", "D"]);
    expect(filterCounts(ps)).toEqual({ out: 2, stale: 1 });
    expect(pointMark(pt("C", null))).toBe("stale");
    expect(pointsFrom("a,b,c,d")).toEqual(["a", "b", "c"]);
  });

  it("has_limits (ux T1): no limits or not checked yet read as dashed off, never nominal or out", () => {
    const none = pt("N", "nominal", "EPS", false);
    const unchecked = pt("U", "no_data", "EPS", true);
    expect(pointMark(none)).toBe("off");
    expect(pointLimits(none)).toEqual({
      mark: "off",
      word: "No limits",
      title: "No limits are defined for this point.",
    });
    expect(pointLimits(unchecked)).toEqual({
      mark: "off",
      word: "Not checked yet",
      title: "Limits are defined, but no sample has been checked yet.",
    });
    // An older read without has_limits marks as before: no_data is stale.
    expect(pointMark(pt("O", "no_data"))).toBe("stale");
    expect(pointMark(pt("L", "nominal", "EPS", true))).toBe("nominal");
    expect(filterCounts([none, unchecked, pt("B", "critical")])).toEqual({ out: 1, stale: 0 });
    expect(filterCounts([pt("O", "no_data")])).toEqual({ out: 0, stale: 1 });
    expect(toCsv(pointIdReader("P"), [{ t: 0, min: 1, mean: 2, max: 3 }])).toBe(
      "time,point,min,mean,max\n1970-01-01T00:00:00.000Z,P,1,2,3",
    );
  });
});

describe("B1 no active alarm (§B1)", () => {
  it("picks the most recently cleared episode", () => {
    const e = (id: string, cleared_at: string | null) => ({ id, cleared_at });
    expect(
      lastCleared([
        e("a", "2026-11-12T01:00:00Z"),
        e("b", null),
        e("c", "2026-11-12T02:31:07Z"),
        e("d", "2026-11-11T23:00:00Z"),
      ])?.id,
    ).toBe("c");
    expect(lastCleared([e("b", null)])).toBeNull();
  });
});

describe("B4 drawing (§B4)", () => {
  const sc = (id: string, over: Partial<FleetSpacecraft> = {}): FleetSpacecraft => ({
    ...spacecraftRow(1),
    id: spacecraftIdReader(id),
    name: id.toUpperCase(),
    plane: 7,
    ...over,
  });
  it("rings the plane by phase, else evenly by slot; marks self and sisters", () => {
    const fleet = [
      sc("a", { phase_deg: 0, slot: 1 }),
      sc("b", { phase_deg: 90, slot: 2 }),
      sc("c", { phase_deg: 180, slot: 3, plane: 8 }),
    ];
    const dots = ringDots(fleet, fleet[0] ?? sc("x"), new Map([["b", "caution" as const]]));
    expect(dots.map((d) => [d.id, d.x, d.y, d.tone])).toEqual([
      ["a", 50, 10, "self"],
      ["b", 90, 50, "caution"],
    ]);
  });
  it("draws a sparkline and says the next AOS", () => {
    const pts = [
      { t: 0, min: 1, mean: 1, max: 1 },
      { t: 10, min: 3, mean: 3, max: 3 },
    ];
    expect(sparkPoints(pts)).toBe("0.0,23.0 80.0,1.0");
    expect(sparkPoints(pts.slice(0, 1))).toBeNull();
    const now = new Date("2026-11-12T00:00:00Z");
    expect(aosShort(sc("a", { next_aos_at: "2026-11-12T00:52:00Z" }), now)).toBe("AOS T−52m");
    expect(aosShort(sc("a", { next_aos_at: "2026-11-12T03:10:00Z" }), now)).toBe("AOS T−3h 10m");
    expect(aosShort(sc("a", { in_contact: true }), now)).toBe("IN CONTACT");
  });
});

describe("G1 protocol line (§11c parity; api c61444ede)", () => {
  const profile = (o: Record<string, unknown> = {}) => ({
    id: "p",
    name: "Block 1",
    version: 6,
    latest_version: 6,
    lifecycle: "active" as const,
    uplink_protocol: "tc" as const,
    packet_protocol: "space_packet" as const,
    ...o,
  });
  it("says what the pinned version runs, dropping what it doesn't say", () => {
    expect(protocolLine(profile())).toBe("TC uplink · Space Packet");
    expect(protocolLine(profile({ uplink_protocol: "uslp", packet_protocol: null }))).toBe(
      "USLP uplink",
    );
    expect(protocolLine(profile({ uplink_protocol: null, packet_protocol: null }))).toBeNull();
  });
});

describe("B2 escalation lines (ux U71 A7)", () => {
  const limitAt = (id: string, at: string) => ({
    id,
    at,
    kind: "limit" as const,
    raw_kind: "limit_violation",
    severity: "critical" as const,
    text: `VBAT limit ${id}`,
    detail: null,
    spacecraft: null,
    refs: {
      alarm_id: null,
      point_id: pointIdReader("EPS.VBAT"),
      command_request_id: null,
      contact_id: null,
      subject: undefined,
    },
    record: null,
  });
  const escalated = {
    id: "x1",
    kind: "escalated" as const,
    actor: null,
    at: "2026-11-08T02:31:41Z",
    sample: { id: "s-9", at: "2026-11-08T02:31:40Z", receipt_time: "2026-11-08T02:31:40.5Z" },
    payload: {},
  };
  it("shows the episode's own escalation with Show sample, hiding that point's limit lines only in its span", () => {
    const lines = logLines(
      [limitAt("in", "2026-11-08T02:31:41Z"), limitAt("before", "2026-11-08T01:00:00Z")],
      {
        pointId: pointIdReader("EPS.VBAT"),
        openedAt: "2026-11-08T02:00:00Z",
        clearedAt: null,
        events: [escalated],
      },
      () => ({ name: "ops.timeline" }),
    );
    expect(lines.map((l) => l.text)).toEqual(["Became critical at 02:31:40Z", "VBAT limit before"]);
    expect(lines[0]?.sampleTo).toEqual({ name: "ops.timeline" });
  });
});
