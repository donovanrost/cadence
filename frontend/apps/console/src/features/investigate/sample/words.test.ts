import { describe, expect, it } from "vite-plus/test";
import { sampleOf, statusOnly } from "./fixtures.ts";
import { cameInThrough, laterBy, realmLine, sampleRows, sampleTime, statusView } from "./words.ts";

const today = "2026-11-08";
const rows = (...a: Parameters<typeof sampleOf>) =>
  sampleRows(sampleOf(...a), today).map((r) => [r.label, r.value]);

describe("ux U80: the Sample aside's rows", () => {
  it("lists Value, Raw, Quality, Generated, Received, Packet, Record, Came in through, in order", () => {
    expect(rows()).toEqual([
      ["Value", "28.1 V"],
      ["Raw", "0x1F40"],
      ["Quality", "Good"],
      ["Generated", "02:08:11.204Z"],
      ["Received", "02:08:12.880Z · 1.7 s later"],
      ["Packet", "HK_EPS v4"],
      ["Record", "The record Cadence uses"],
      ["Came in through", "Fairbanks · binding Earendil telemetry v3"],
    ]);
  });

  it("puts the date in front of a time that isn't today (§4)", () => {
    expect(sampleTime("2026-11-07T23:59:59.5Z", today)).toBe("11-07 23:59:59.500Z");
  });

  it("says how much later it arrived, and nothing when that isn't later", () => {
    const g = "2026-11-08T02:00:00Z";
    expect(laterBy(g, "2026-11-08T02:03:10Z")).toBe("3 min later");
    expect(laterBy(g, "2026-11-08T04:10:00Z")).toBe("2 h later");
    expect(laterBy(g, g)).toBeNull();
    expect(laterBy(null, g)).toBeNull();
    expect(rows({ generation_time: null }).map(([k]) => k)).not.toContain("Generated");
  });

  it("gives each value state ux's words, with no text when it's too large", () => {
    const value = (state: string, text: string | null) =>
      rows({ engineering_value: { state, text, format: null } })[0]?.[1];
    expect(value("not_recorded", null)).toBe("Not recorded");
    expect(value("unsupported", null)).toBe("Can't be shown for this point type");
    expect(value("limited", null)).toBe("Too large to show here");
  });

  it("marks Suspect and Bad quality and a conflicting record", () => {
    const r = rows({ quality: "bad" }, {}, { validity_state: "conflict" });
    expect(r).toContainEqual(["Quality", "▲ Bad"]);
    expect(r).toContainEqual(["Record", "▲ Conflicts with another record for this time"]);
  });

  it("has no Record row without a validity state, and advisory reads as kept for reference", () => {
    expect(rows({}, {}, { validity_state: null }).map(([k]) => k)).not.toContain("Record");
    expect(rows({}, {}, { validity_state: "advisory" })).toContainEqual([
      "Record",
      "Kept for reference: not the record Cadence uses",
    ]);
  });

  it("never shows an id for a missing name (U25)", () => {
    const s = (src: Record<string, unknown>) => sampleOf({}, src).source;
    expect(cameInThrough(s({ endpoint_label: null }))).toBe("binding Earendil telemetry v3");
    expect(cameInThrough(s({ binding_label: null }))).toBe("Fairbanks");
    expect(cameInThrough(s({ endpoint_label: null, binding_label: null }))).toBe("Ground history");
    expect(
      cameInThrough(s({ endpoint_label: null, binding_label: null, data_source_name: null })),
    ).toBeNull();
    expect(rows({}, {}, { packet_definition_name: null })).toContainEqual([
      "Packet",
      "An unnamed packet definition v4",
    ]);
    expect(rows().flat().join(" ")).not.toMatch(/\b(b-1|ep-1|ds-1|pd-1|s-1)\b/);
  });

  it("names the realm only when it isn't flight", () => {
    const realm = (src: Record<string, unknown>) => realmLine(sampleOf({}, src).source);
    expect(realm({})).toBeNull();
    expect(realm({ realm: "replay", replay_run_id: "r-14", replay_run_label: "14" })).toBe(
      "Replay · run 14",
    );
    expect(realm({ realm: "rehearsal" })).toBe("Rehearsal");
    expect(realm({ realm: "simulation" })).toBe("Simulation");
  });
});

describe("ux U80: statuses instead of rows", () => {
  it("says what each status means, with its action", () => {
    const v = (s: string) => statusView(statusOnly(s).status, "02:08:11Z");
    expect(v("not_found")).toEqual({
      line: "Cadence couldn't find this sample in the history store.",
      action: null,
    });
    expect(v("ambiguous")?.line).toBe(
      "More than one sample matches 02:08:11Z, so Cadence can't tell which one this is.",
    );
    expect(v("ambiguous")?.action).toBe("show-at");
    expect(v("timeout")?.action).toBe("retry");
    expect(v("unavailable")?.action).toBe("retry");
    expect(v("unsupported")?.line).toBe("This data source can't look up a single sample.");
  });
});
