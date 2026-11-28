import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import {
  conditionText,
  detailWords,
  freshnessWord,
  markState,
  pointsReader,
  sourceWords,
  valueText,
  type PointCondition,
} from "./api.ts";

/** A row as the server sends it (docs/apogee/api/ops.md, point-conditions). */
const wire = (over: Record<string, unknown> = {}) => ({
  point_id: "HK.bus_voltage",
  point_name: "Bus voltage",
  unit: "V",
  source: "ground_limit",
  policy_id: null,
  condition: "caution",
  raw_limit_state: "yellow_high",
  evaluated: true,
  evaluated_at: "2026-11-27T12:00:00.000000Z",
  entered_at: "2026-11-27T11:50:00.000000Z",
  entered_at_is_lower_bound: false,
  value: 33.2,
  last_sample_at: "2026-11-27T11:59:30.000000Z",
  freshness: "fresh",
  ...over,
});

function row(over: Record<string, unknown> = {}): PointCondition {
  const r = decode(pointsReader, [wire(over)]);
  if (!r.ok) throw new Error(r.error.message);
  const first = r.value[0];
  if (!first) throw new Error("no row");
  return first;
}

describe("the point conditions reader", () => {
  it("reads a ground-limit row and a live row", () => {
    const ground = row();
    expect(ground.point_name).toBe("Bus voltage");
    expect(ground.entered_at).toBe("2026-11-27T11:50:00.000000Z");

    const live = row({
      source: "catalog_monitoring",
      policy_id: "pol-1",
      raw_limit_state: null,
      evaluated_at: null,
      value: null,
      condition: "critical",
    });
    expect(live.value).toBeNull();
    expect(live.policy_id).toBe("pol-1");
  });

  it("keeps a source or condition this console does not know, and says the server's word", () => {
    const odd = row({ source: "radar", condition: "elevated" });
    expect(sourceWords(odd)).toBe("radar");
    expect(conditionText(odd)).toBe("elevated");
  });

  it("refuses a row with no condition", () => {
    const r = decode(pointsReader, [{ ...wire(), condition: undefined }]);
    expect(r.ok).toBe(false);
  });
});

describe("what a row says", () => {
  it("a critical or caution point shows its condition, stale or not", () => {
    expect(markState(row({ condition: "critical", freshness: "stale" }))).toBe("crit");
    expect(markState(row({ condition: "caution" }))).toBe("caution");
    expect(freshnessWord(row({ condition: "critical", freshness: "stale" }))).toBe("STALE");
  });

  it("a stale nominal point never reads healthy", () => {
    const stale = row({ condition: "nominal", freshness: "stale" });
    expect(markState(stale)).toBe("stale");
    expect(freshnessWord(stale)).toBe("STALE");
    expect(
      freshnessWord(row({ condition: "nominal", freshness: "stale", last_sample_at: null })),
    ).toBe("NEVER SAMPLED");
  });

  it("an unknown sample time is said, and is not healthy either", () => {
    const unknown = row({ condition: "nominal", freshness: "unknown", last_sample_at: null });
    expect(markState(unknown)).toBe("off");
    expect(freshnessWord(unknown)).toBe("SAMPLE TIME UNKNOWN");
  });

  it("a fresh nominal point is nominal, and a point never evaluated is not", () => {
    expect(markState(row({ condition: "nominal" }))).toBe("nominal");
    expect(freshnessWord(row({ condition: "nominal" }))).toBeNull();
    const never = row({
      condition: "nominal",
      evaluated: false,
      evaluated_at: null,
      entered_at: null,
    });
    expect(markState(never)).toBe("off");
    expect(detailWords(never)).toBe("Not evaluated yet");
  });

  it("the detail is the limit in words for a ground limit and the rule for a live row", () => {
    expect(detailWords(row())).toBe("above yellow limit");
    expect(detailWords(row({ raw_limit_state: "red_low" }))).toBe("below red limit");
    expect(detailWords(row({ raw_limit_state: "mystery_state" }))).toBe("mystery_state");
    expect(detailWords(row({ source: "catalog_monitoring", policy_id: "pol-9" }))).toBe("pol-9");
  });

  it("a value is shown with its unit, and a live row has none", () => {
    expect(valueText(row())).toBe("33.2 V");
    expect(valueText(row({ value: null }))).toBe("—");
  });
});
