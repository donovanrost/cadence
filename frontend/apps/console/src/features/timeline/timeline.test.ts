import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { eventsReader, type MissionEvent } from "./api.ts";
import { byHour, densityBars, densityBucketS, severityState } from "./model.ts";

const ev = (id: string, at: string, severity: MissionEvent["severity"] = "info"): MissionEvent => ({
  id,
  at,
  kind: "limit",
  severity,
  raw_kind: "limit_violation",
  text: "VBAT crossed red low",
  detail: null,
  spacecraft: null,
  refs: { alarm_id: null, point_id: null, command_request_id: null, contact_id: null },
});

describe("timeline", () => {
  it("decodes the proposed events shape and rejects unknown kinds", () => {
    const body = {
      from: "2026-11-08T00:00:00Z",
      to: "2026-11-08T01:00:00Z",
      events: [ev("a", "2026-11-08T00:10:00Z")],
    };
    expect(decode(eventsReader, body).ok).toBe(true);
    expect(
      decode(eventsReader, { ...body, events: [{ ...ev("a", "2026-11-08T00:10:00Z"), kind: "x" }] })
        .ok,
    ).toBe(false);
  });

  it("groups newest first under UTC hours", () => {
    const groups = byHour([
      ev("a", "2026-11-08T01:05:00Z"),
      ev("b", "2026-11-08T02:30:00Z"),
      { ...ev("c", "2026-11-08T02:10:00Z"), text: "AOS Svalbard" },
    ]);
    expect(groups.map((g) => [g.hour, g.rows.map((r) => r.event.id)])).toEqual([
      ["2026-11-08 02:00Z", ["b", "c"]],
      ["2026-11-08 01:00Z", ["a"]],
    ]);
  });

  it("collapses consecutive identical events into one row with a count", () => {
    const [group] = byHour([
      ev("a", "2026-11-08T02:30:03Z"),
      ev("b", "2026-11-08T02:30:02Z"),
      ev("c", "2026-11-08T02:30:01Z"),
      { ...ev("d", "2026-11-08T02:29:00Z"), text: "Something else" },
    ]);
    expect(group?.rows.map((r) => [r.event.id, r.count, r.firstAt])).toEqual([
      ["a", 3, "2026-11-08T02:30:01Z"],
      ["d", 1, "2026-11-08T02:29:00Z"],
    ]);
  });

  it("folds the same event across more than three spacecraft in one minute (ux 6)", () => {
    const sc = (n: number) => ({ id: `sc-${n}`, name: `EARENDIL-${n}`, scid: n });
    const realized = (n: number) => ({
      ...ev(`r${n}`, "2026-11-08T02:30:05Z"),
      kind: "contact" as const,
      text: "Realized contact interval",
      spacecraft: sc(n),
    });
    const [group] = byHour([1, 2, 3, 4, 5].map(realized));
    expect(group?.rows).toHaveLength(1);
    expect(group?.rows[0]?.members).toHaveLength(5);
    const [few] = byHour([1, 2, 3].map(realized));
    expect(few?.rows).toHaveLength(3);
  });

  it("sizes density buckets and stacks severities", () => {
    expect(densityBucketS(24 * 3_600_000)).toBe(900);
    expect(densityBucketS(3_600_000)).toBe(60);
    const { bars, max } = densityBars({
      bucket_s: 900,
      truncated: false,
      buckets: [{ t: "2026-11-08T00:00:00Z", critical: 1, caution: 0, nominal: 0, info: 3 }],
    });
    expect(max).toBe(4);
    expect(bars[0]?.stack.map((s) => [s.severity, s.from, s.to])).toEqual([
      ["critical", 0, 0.25],
      ["info", 0.25, 1],
    ]);
  });

  it("maps severities to marks", () => {
    expect(severityState("info")).toBe("neutral");
    expect(severityState("critical")).toBe("crit");
  });
});
