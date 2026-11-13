import { describe, expect, it } from "vite-plus/test";
import { saveOutcome } from "./saveOutcome.ts";
import { hostRefusal, setupSurfaces } from "./surfaces.ts";

const receipt = { receiptId: "r1", completedAt: "2026-11-13T03:00:00Z", result: {} };

describe("L9 save-outcome seam (DECISIONS #77)", () => {
  it("says what each app's own save did, never 'staged'", () => {
    expect(saveOutcome("limits", "save_limit_definition", receipt)).toEqual({
      kind: "saved",
      text: "Saved.",
    });
    expect(saveOutcome("telemetry_decom", "request_activation", receipt)).toEqual({
      kind: "activation_requested",
      text: "Activation requested. It applies once it's approved.",
    });
    expect(saveOutcome("telemetry_decom", "disable", receipt)).toBeNull();
    expect(saveOutcome("someone_else", "save_x", receipt)).toBeNull();
  });
});

describe("L9 host frame helpers", () => {
  const s = (surface_id: string, order: number, area: "setup" | "ops") => ({
    surface_id,
    label: surface_id,
    order,
    purpose: "configuration",
    area,
    scope: "mission" as const,
  });
  it("tabs the Setup surfaces in the app's order", () => {
    expect(
      setupSurfaces([
        s("activity", 2, "setup"),
        s("monitor", 0, "ops"),
        s("manage", 1, "setup"),
      ]).map((x) => x.surface_id),
    ).toEqual(["manage", "activity"]);
  });
  it("explains not-installed and unknown", () => {
    expect(
      hostRefusal({
        kind: "conflict",
        code: "application_not_installed",
        message: "",
        details: null,
      }),
    ).toBe("not_installed");
    expect(hostRefusal({ kind: "not_found", code: "surface_not_found", message: "" })).toBe(
      "unknown",
    );
    expect(hostRefusal({ kind: "unavailable", status: 500, message: "" })).toBeNull();
  });
});
