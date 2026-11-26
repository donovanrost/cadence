import { describe, expect, it } from "vite-plus/test";
import { retiredSurfaceHome, surfaceLink, surfaceParams } from "./surfaces.ts";

describe("app surface deep links (ux U42)", () => {
  it("passes only the keys the app's surface query accepts, single values only", () => {
    expect(
      surfaceParams("derived_telemetry", { definition: "dd_1", edit: "1", page: ["1", "2"] }),
    ).toEqual({ definition: "dd_1" });
    // An app without declared keys gets none, so a stray ?x= can't fail its surface.
    expect(surfaceParams("limits", { definition: "dd_1" })).toEqual({});
  });

  it("keeps a surface's own links in the console (they used to leave for the legacy page)", () => {
    expect(
      surfaceLink(
        "/missions/mission-1/applications/derived_telemetry/manage?definition=dd_1&page=2",
        "mission-1",
      ),
    ).toEqual({
      appKey: "derived_telemetry",
      surface: "manage",
      query: { definition: "dd_1", page: "2" },
    });
    expect(
      surfaceLink("/missions/other/applications/derived_telemetry/manage", "mission-1"),
    ).toBeNull();
    expect(surfaceLink("/missions/mission-1/ops/fleet", "mission-1")).toBeNull();
    expect(surfaceLink("https://example.com/elsewhere", "mission-1")).toBeNull();
  });
});

describe("retired surfaces (sweep row 2, ux)", () => {
  it("send spacecraft's removed create/edit forms to their console homes", () => {
    expect(retiredSurfaceHome("spacecraft", "new", null)).toEqual({ name: "setup.spacecraft.new" });
    expect(retiredSurfaceHome("spacecraft", "profile_new", null)).toEqual({
      name: "setup.profile.new",
    });
    expect(retiredSurfaceHome("spacecraft", "edit", "sc-1")).toEqual({
      name: "setup.spacecraft.one",
      params: { spacecraftId: "sc-1" },
    });
    expect(retiredSurfaceHome("spacecraft", "edit", null)).toEqual({ name: "setup.spacecraft" });
    expect(retiredSurfaceHome("spacecraft", "show", "sc-1")).toBeNull();
    expect(retiredSurfaceHome("comms", "transport_new", null)).toBeNull();
  });
});
