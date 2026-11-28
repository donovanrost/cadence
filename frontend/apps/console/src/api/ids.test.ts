import { describe, expect, it } from "vite-plus/test";
import { decode } from "./decode.ts";
import {
  dashboardId,
  dashboardIdParam,
  dashboardIdSegment,
  missionId,
  organizationId,
  pointId,
  pointIdParam,
  scid,
  scidParam,
  spacecraftId,
  spacecraftIdParam,
  stationIdParam,
  type DashboardId,
  type MissionId,
  type OrganizationId,
  type PointId,
  type SpacecraftId,
} from "./ids.ts";

describe("branded ids", () => {
  it("decodes ids as tokens and SCIDs as non-negative integers", () => {
    expect(decode(spacecraftId, "sc-1")).toEqual({ ok: true, value: "sc-1" });
    expect(decode(spacecraftId, "").ok).toBe(false);
    expect(decode(scid, 42)).toEqual({ ok: true, value: 42 });
    expect(decode(scid, -1).ok).toBe(false);
    expect(decode(scid, "42").ok).toBe(false);
  });

  it("reads route params", () => {
    expect(spacecraftIdParam("sc-1")).toBe("sc-1");
    expect(spacecraftIdParam(["sc-1", "x"])).toBe("sc-1");
    expect(spacecraftIdParam("")).toBeNull();
    expect(stationIdParam(undefined)).toBeNull();
    expect(scidParam("204")).toBe(204);
    expect(scidParam("")).toBeNull();
    expect(scidParam("sc-1")).toBeNull();
  });

  it("keeps the id spaces apart at compile time", () => {
    const takesMission = (id: MissionId) => id;
    const sc = spacecraftIdParam("sc-1");
    if (sc === null) throw new Error("unreachable");
    // @ts-expect-error a SpacecraftId is not a MissionId
    takesMission(sc);
    // @ts-expect-error a plain string is not a branded id
    takesMission("m-1");
    const takesSpacecraft = (id: SpacecraftId) => id;
    // @ts-expect-error a SCID is not a spacecraft id
    takesSpacecraft(scidParam("1") ?? 0);
    const decoded = decode(missionId, "m-1");
    if (decoded.ok) expect(takesMission(decoded.value)).toBe("m-1");
  });

  // #193: the audit's remaining ids (§1.2): organizations, dashboards and telemetry points.
  it("decodes organization, dashboard and point ids, and reads their params", () => {
    expect(decode(organizationId, "org-1")).toEqual({ ok: true, value: "org-1" });
    expect(decode(dashboardId, "").ok).toBe(false);
    expect(decode(pointId, "EPS.VBAT")).toEqual({ ok: true, value: "EPS.VBAT" });
    expect(pointIdParam("EPS.VBAT")).toBe("EPS.VBAT");
    expect(pointIdParam(" EPS.VBAT")).toBeNull();
    expect(dashboardIdParam(undefined)).toBeNull();
    expect(dashboardIdSegment("dash-1")).toBe("dash-1");
  });

  it("keeps points, dashboards and organizations apart from the other ids", () => {
    const takesPoint = (id: PointId) => id;
    const takesDashboard = (id: DashboardId) => id;
    const takesOrganization = (id: OrganizationId) => id;
    const sc = spacecraftIdParam("sc-1");
    const point = pointIdParam("EPS.VBAT");
    if (sc === null || point === null) throw new Error("unreachable");
    // @ts-expect-error a SpacecraftId is not a PointId (Investigate's sibling arguments, audit §1.2 #4)
    takesPoint(sc);
    const takesSpacecraft = (id: SpacecraftId) => id;
    // @ts-expect-error a PointId is not a SpacecraftId
    takesSpacecraft(point);
    // @ts-expect-error a plain string is not a DashboardId
    takesDashboard("dash-1");
    const mission = decode(missionId, "m-1");
    if (!mission.ok) throw new Error("unreachable");
    // @ts-expect-error a MissionId is not an OrganizationId
    takesOrganization(mission.value);
    expect(takesPoint(point)).toBe("EPS.VBAT");
  });
});
