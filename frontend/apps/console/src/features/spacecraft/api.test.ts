import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { directoryReader, matchesFilter, summarize } from "./api.ts";

const row = (extra: Record<string, unknown> = {}) => ({
  id: "spacecraft-1",
  name: "EARENDIL-312",
  scid: 312,
  norad_id: null,
  plane: 13,
  slot: 12,
  profile: { id: "type_1", name: "Block 1", version: 4 },
  routing_rule_count: 6,
  ready: true,
  last_received_at: "2026-11-08T02:41:15Z",
  ...extra,
});

describe("directoryReader", () => {
  it("reads identity columns and keeps null distinct", () => {
    const result = decode(directoryReader, {
      spacecraft: [
        row(),
        row({
          id: "spacecraft-2",
          scid: null,
          profile: null,
          routing_rule_count: 0,
          ready: false,
          last_received_at: null,
        }),
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
      withoutRoute: 1,
      neverHeard: 1,
    });
  });

  it("rejects a ready row that lacks a routing rule", () => {
    const result = decode(directoryReader, { spacecraft: [row({ routing_rule_count: 0 })] });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.path).toBe("spacecraft[0].ready");
  });

  it("rejects missing columns rather than defaulting them", () => {
    const { plane: _plane, ...withoutPlane } = row();
    expect(decode(directoryReader, { spacecraft: [withoutPlane] }).ok).toBe(false);
  });
});

describe("matchesFilter", () => {
  const result = decode(directoryReader, { spacecraft: [row()] });
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

describe("S9 (#313): the directory's SCIDs in use", () => {
  it("reads the server's next free SCID and SCIDs in use; null when it doesn't send them", () => {
    const sent = decode(directoryReader, {
      spacecraft: [],
      next_free_scid: 3,
      scids_in_use: [1, 2, 7],
    });
    expect(sent.ok && sent.value.scids).toEqual({ next: 3, inUse: [1, 2, 7] });
    const full = decode(directoryReader, {
      spacecraft: [],
      next_free_scid: null,
      scids_in_use: [],
    });
    expect(full.ok && full.value.scids).toEqual({ next: null, inUse: [] });
    const before = decode(directoryReader, { spacecraft: [] });
    expect(before.ok && before.value.scids).toBeNull();
  });

  it("derives the next free SCID from the list when the server leaves it out (mms-engineer)", () => {
    const r = decode(directoryReader, { spacecraft: [], scids_in_use: [1, 2, 4] });
    expect(r.ok && r.value.scids).toEqual({ next: 3, inUse: [1, 2, 4] });
    const taken = Array.from({ length: 1023 }, (_, i) => i + 1);
    const full = decode(directoryReader, { spacecraft: [], scids_in_use: taken });
    expect(full.ok && full.value.scids?.next).toBeNull();
  });

  it("refuses a SCID outside 0..1023", () => {
    expect(decode(directoryReader, { spacecraft: [], scids_in_use: [1024] }).ok).toBe(false);
    expect(
      decode(directoryReader, { spacecraft: [], next_free_scid: -1, scids_in_use: [] }).ok,
    ).toBe(false);
  });
});
