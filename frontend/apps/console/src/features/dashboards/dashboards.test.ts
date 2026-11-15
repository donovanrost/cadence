import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { workspaceSnapshot, type WidgetType } from "./model/snapshot.ts";
import { limitMark, table, valueTile, worstLimitState } from "./model/widget-data.ts";
import { selectionFromQuery, selectionParams } from "./model/time-range.ts";
import { snapshotJson } from "./fixtures.test-support.ts";

const read = (value: unknown) => decode(workspaceSnapshot, value);

describe("workspace snapshot decoder", () => {
  it("accepts the server snapshot, ready and unavailable placements alike", () => {
    const result = read(snapshotJson());
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.placements.map((p) => p.status)).toEqual(["ready", "unavailable"]);
  });

  it("rejects ragged frame columns", () => {
    const s = snapshotJson("time_series");
    const fields = s.placements[0]?.frames[0]?.fields;
    fields?.[1]?.values.pop();
    expect(read(s).ok).toBe(false);
  });

  it("rejects a placement in a section the dashboard doesn't have", () => {
    const s = snapshotJson();
    if (s.placements[0]) s.placements[0].section_id = "nowhere";
    const result = read(s);
    expect(result.ok ? null : result.error.path).toBe(".placements[0].section_id");
  });

  it("rejects an unavailable placement that carries data", () => {
    const s = snapshotJson();
    const gone = s.placements[1];
    if (gone) gone.frames = s.placements[0]?.frames ?? [];
    expect(read(s).ok).toBe(false);
  });

  it("rejects cells that don't match their column's kind", () => {
    const s = snapshotJson();
    const values = s.placements[0]?.frames[0]?.fields[1]?.values;
    if (values) values[0] = "28.4";
    expect(read(s).ok).toBe(false);
  });

  it("rejects a staged document shown to a non-author", () => {
    const s = { ...snapshotJson(), document_mode: "draft_preview" };
    expect(read(s).ok).toBe(false);
  });
});

describe("widget projections", () => {
  const ready = (type: WidgetType) => {
    const r = read(snapshotJson(type));
    if (!r.ok || r.value.placements[0]?.status !== "ready") throw new Error("fixture");
    return r.value.placements[0];
  };

  it("formats a value tile with its unit", () => {
    expect(valueTile(ready("value_tile"))).toMatchObject({
      kind: "value",
      text: "28.40",
      unit: "V",
    });
  });

  it("maps ground limit states onto the Apogee grammar", () => {
    const p = ready("data_table");
    expect(worstLimitState(p)).toBe("red");
    expect(limitMark.red).toBe("crit");
    expect(table(p).rows[0]?.cells.find((c) => c.state)?.state).toBe("red");
  });
});

describe("viewer range in the URL", () => {
  it("reads sliding ranges up to 24 h and absolute ranges up to 31 days", () => {
    expect(selectionFromQuery("now-6h", "now")).toEqual({ kind: "sliding", seconds: 21_600 });
    expect(selectionFromQuery("now-2d", "now")).toEqual({ kind: "default" });
    expect(selectionFromQuery("2026-11-12T21:00:00Z", "2026-11-12T23:00:00Z")).toEqual({
      kind: "absolute",
      from: "2026-11-12T21:00:00Z",
      to: "2026-11-12T23:00:00Z",
    });
    expect(selectionFromQuery("2026-11-12T23:00:00Z", "2026-11-12T21:00:00Z")).toEqual({
      kind: "default",
    });
  });

  it("round-trips a sliding selection", () => {
    const params = selectionParams({ kind: "sliding", seconds: 3_600 });
    expect(selectionFromQuery(params.from ?? "", params.to ?? "")).toEqual({
      kind: "sliding",
      seconds: 3_600,
    });
  });
});
