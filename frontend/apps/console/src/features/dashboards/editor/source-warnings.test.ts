import { describe, expect, it } from "vite-plus/test";
import type { SourceWarning } from "./contracts.ts";
import { warningsText, warningText } from "./source-warnings.ts";

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

describe("source warnings", () => {
  it("names the source, realm, time and widget count", () => {
    expect(warningText(warning())).toBe(
      "Telemetry (flight) wasn't answering at 09:12Z; 3 widgets may stay empty until it does.",
    );
  });
  it("words a degraded source and a single widget", () => {
    expect(warningText(warning({ code: "source_degraded", placement_ids: ["dash_widget_a"] }))).toBe(
      "Telemetry (flight) was answering slowly at 09:12Z; 1 widget may show partial data.",
    );
  });
  it("degrades unknown values to generic words, and no time without a health row", () => {
    const w = warning({
      logical_source: { unrecognized: "archive" },
      realm: { unrecognized: "lab" },
      observed_at: null,
    });
    expect(warningText(w)).toBe(
      "A data source wasn't answering; 3 widgets may stay empty until it does.",
    );
  });
  it("falls back to the server's sentence for an unknown code", () => {
    expect(warningText(warning({ code: { unrecognized: "source_flaky" } }))).toBe(
      "Dashboard source is unavailable for the publish context.",
    );
  });
  it("is null when the write had no warnings (or the server sent none yet)", () => {
    expect(warningsText("Saved.", [])).toBeNull();
    expect(warningsText("Saved.", undefined)).toBeNull();
    expect(warningsText("Saved.", [warning(), warning({ realm: null })])).toBe(
      "Saved. Telemetry (flight) wasn't answering at 09:12Z; 3 widgets may stay empty until it does. Telemetry wasn't answering at 09:12Z; 3 widgets may stay empty until it does.",
    );
  });
});
