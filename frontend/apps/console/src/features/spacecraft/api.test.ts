import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { fleetDirectoryReader, matchesFilter, summarize } from "./api.ts";

const row = (extra: Record<string, unknown> = {}) => ({
  id: "spacecraft-1",
  name: "EARENDIL-312",
  scid: 312,
  plane: 13,
  slot: 12,
  profile: { id: "type_1", name: "Block 1", version: 4 },
  last_received_at: "2026-11-08T02:41:15Z",
  // Ops-only columns are ignored by the directory reader.
  state: "nominal",
  ...extra,
});

describe("fleetDirectoryReader", () => {
  it("reads identity columns and keeps null distinct", () => {
    const result = decode(fleetDirectoryReader, {
      spacecraft: [
        row(),
        row({ id: "spacecraft-2", scid: null, profile: null, last_received_at: null }),
      ],
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.spacecraft[1]).toMatchObject({
      scid: null,
      profile: null,
      lastReceivedAt: null,
    });
    expect(summarize(result.value)).toEqual({
      total: 2,
      profiles: 1,
      withoutProfile: 1,
      withoutScid: 1,
      neverHeard: 1,
    });
  });

  it("rejects missing columns rather than defaulting them", () => {
    const { plane: _plane, ...withoutPlane } = row();
    expect(decode(fleetDirectoryReader, { spacecraft: [withoutPlane] }).ok).toBe(false);
  });
});

describe("matchesFilter", () => {
  const result = decode(fleetDirectoryReader, { spacecraft: [row()] });
  if (!result.ok) throw result.error;
  const sc = result.value.spacecraft[0];
  if (!sc) throw new Error("fixture");

  it("matches name, profile and SCID prefix", () => {
    expect(matchesFilter(sc, "earendil")).toBe(true);
    expect(matchesFilter(sc, "block")).toBe(true);
    expect(matchesFilter(sc, "31")).toBe(true);
    expect(matchesFilter(sc, "99")).toBe(false);
    expect(matchesFilter(sc, "  ")).toBe(true);
  });
});
