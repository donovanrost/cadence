import { describe, expect, it } from "vite-plus/test";
import {
  isSubjectSurface,
  retiredSurfaceHome,
  subjectSurfaceHome,
  surfaceLink,
  surfaceParams,
} from "./surfaces.ts";

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
    expect(retiredSurfaceHome("comms", "new", null)).toBeNull();
  });

  it("send comms' removed create forms (batch 1) to the console's add forms", () => {
    expect(retiredSurfaceHome("comms", "transport_new", null)).toEqual({
      name: "setup.comms.transports",
      params: { transportId: "new" },
    });
    expect(retiredSurfaceHome("comms", "ground_station_new", null)).toEqual({
      name: "setup.stations",
      params: { stationId: "new" },
    });
    // routing_new stays until batch 2; its form is the app's.
    expect(retiredSurfaceHome("comms", "routing_new", null)).toBeNull();
  });
});

describe("one-record surfaces (lead, qa 11-16)", () => {
  it("names the comms record surfaces and sends each to the console screen that owns it", () => {
    expect(
      subjectSurfaceHome("comms", "ground_station_edit", { ground_station_id: "gs-1" }),
    ).toEqual({
      name: "setup.stations",
      params: { stationId: "gs-1" },
    });
    expect(subjectSurfaceHome("comms", "ground_station", {})).toEqual({ name: "setup.stations" });
    expect(subjectSurfaceHome("comms", "transport", { transport_id: "tr-9" })).toEqual({
      name: "setup.comms.transports",
      params: { transportId: "tr-9" },
    });
    expect(subjectSurfaceHome("comms", "routing_detail", { routing_rule_id: "r-2" })).toEqual({
      name: "setup.comms",
    });
  });

  it("leaves list, new and other apps' surfaces alone, and ignores a repeated or empty id", () => {
    for (const surface of ["overview", "transports", "ground_stations", "ground_station_new"])
      expect(isSubjectSurface("comms", surface)).toBe(false);
    expect(isSubjectSurface("derived_telemetry", "ground_station")).toBe(false);
    expect(isSubjectSurface("comms", "ground_station_edit")).toBe(true);
    expect(
      subjectSurfaceHome("comms", "ground_station", { ground_station_id: ["a", "b"] }),
    ).toEqual({
      name: "setup.stations",
    });
    expect(subjectSurfaceHome("comms", "transport", { transport_id: "" })).toEqual({
      name: "setup.comms.transports",
    });
  });
});
