import { describe, expect, it } from "vite-plus/test";
import { decode } from "./decode.ts";
import {
  missionId,
  scid,
  scidParam,
  spacecraftId,
  spacecraftIdParam,
  stationIdParam,
  type MissionId,
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
});
