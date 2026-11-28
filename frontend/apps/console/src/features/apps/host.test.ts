import { describe, expect, it } from "vite-plus/test";
import { hostRefusal, setupSurfaces } from "./surfaces.ts";

describe("L9 host frame helpers", () => {
  const s = (surface_id: string, order: number, area: "setup" | "ops") => ({
    surface_id,
    label: surface_id,
    order,
    purpose: "configuration" as const,
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

describe("L9 status line (ux #77)", () => {
  it("says who requested the pending activation and when", async () => {
    const { pendingLine } = await import("./host.ts");
    const { lostText } = await import("./hostBridge.ts");
    const at = (iso: string) => iso.slice(11, 16) + "Z";
    const base = { state: "activation_pending" as const, label: null, version: "3" };
    expect(
      pendingLine(
        {
          ...base,
          activation_request: {
            requested_by: { kind: "user" as const, id: null, name: "Mira K." },
            requested_at: "2026-11-13T02:10:00Z",
          },
        },
        at,
      ),
    ).toBe("Waiting for activation approval · requested by Mira K. at 02:10Z");
    expect(pendingLine({ ...base, activation_request: null }, at)).toBe(
      "Waiting for activation approval",
    );
    expect(pendingLine({ ...base, state: "active", activation_request: null }, at)).toBeNull();
    expect(lostText(true)).toContain("Changes you haven't saved here will be lost.");
  });
});
