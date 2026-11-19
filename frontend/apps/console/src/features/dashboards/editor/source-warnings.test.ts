import { describe, expect, it } from "vite-plus/test";
import type { SourceWarning } from "./contracts.ts";
import { warningsText, warningText } from "./source-warnings.ts";

const now = new Date("2026-11-14T10:00:00Z");
const warning = (over: Partial<SourceWarning> = {}): SourceWarning => ({
  code: "source_unavailable",
  logical_source: "telemetry",
  realm: "flight",
  reasons: ["source_unavailable"],
  observed_at: "2026-11-14T09:12:30Z",
  placement_ids: ["dash_widget_a", "dash_widget_b", "dash_widget_c"],
  message: "Dashboard source is unavailable for the publish context.",
  ...over,
});

describe("source warnings (ux words)", () => {
  it("leaves flight unnamed and says when health was checked", () => {
    expect(warningText(warning(), now)).toBe(
      "Telemetry wasn't answering when checked at 09:12Z; 3 widgets may stay empty until it does.",
    );
  });
  it("names any other realm, and dates a check from another day", () => {
    const w = warning({ realm: "replay", observed_at: "2026-11-13T23:40:00Z" });
    expect(warningText(w, now)).toBe(
      "Telemetry (replay) wasn't answering when checked at 11-13 23:40Z; 3 widgets may stay empty until it does.",
    );
  });
  it("words a degraded source and a single widget", () => {
    const w = warning({ code: "source_degraded", placement_ids: ["dash_widget_a"] });
    expect(warningText(w, now)).toBe(
      "Telemetry was slow when checked at 09:12Z; 1 widget may load slowly or show partial data.",
    );
  });
  it("drops the widget clause with no placements, and the time with no health row", () => {
    expect(warningText(warning({ placement_ids: [] }), now)).toBe(
      "Telemetry wasn't answering when checked at 09:12Z.",
    );
    expect(warningText(warning({ observed_at: null, placement_ids: [] }), now)).toBe(
      "Telemetry wasn't answering.",
    );
  });
  it("degrades unknown values to generic words", () => {
    const w = warning({
      logical_source: { unrecognized: "archive" },
      realm: { unrecognized: "lab" },
    });
    expect(warningText(w, now)).toBe(
      "A data source wasn't answering when checked at 09:12Z; 3 widgets may stay empty until it does.",
    );
  });
  it("falls back to the server's sentence for an unknown code", () => {
    expect(warningText(warning({ code: { unrecognized: "source_flaky" } }), now)).toBe(
      "Dashboard source is unavailable for the publish context.",
    );
  });
  it("is null when the write had no warnings (or the server sent none yet)", () => {
    expect(warningsText("Saved.", [], now)).toBeNull();
    expect(warningsText("Saved.", undefined, now)).toBeNull();
    expect(warningsText("Saved.", [warning({ placement_ids: [] })], now)).toBe(
      "Saved. Telemetry wasn't answering when checked at 09:12Z.",
    );
  });
});
