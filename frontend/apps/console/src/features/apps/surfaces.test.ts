import { describe, expect, it } from "vite-plus/test";
import { surfaceLink } from "./surfaces.ts";

describe("app surface links (ux U42)", () => {
  it("keeps a surface's own links in the console (they used to leave for the legacy page)", () => {
    expect(
      surfaceLink(
        "/missions/mission-1/applications/telemetry_decom/configuration?page=2",
        "mission-1",
      ),
    ).toEqual({
      appKey: "telemetry_decom",
      surface: "configuration",
      query: { page: "2" },
    });
    expect(
      surfaceLink("/missions/other/applications/telemetry_decom/configuration", "mission-1"),
    ).toBeNull();
    expect(surfaceLink("/missions/mission-1/ops/fleet", "mission-1")).toBeNull();
    expect(surfaceLink("https://example.com/elsewhere", "mission-1")).toBeNull();
  });
});
