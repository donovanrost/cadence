import { describe, expect, it } from "vite-plus/test";
import { scid as scidOf, spacecraftId } from "@/api";
import type { SpacecraftRow } from "../api.ts";
import { checkClashes, generateRows, manifestRows, nextFreeScid, rangeLabel } from "./batch.ts";
import { guessMapping, parseCsv, readRows } from "./manifest.ts";
import { expandName, parsePattern } from "./naming.ts";

const pattern = (source: string) => {
  const result = parsePattern(source);
  if (!result.ok) throw new Error(result.message);
  return result.pattern;
};

const existing = (name: string, scid: number | null): SpacecraftRow => ({
  id: spacecraftId(`sc-${name}`),
  name,
  scid: scid === null ? null : scidOf(scid),
  noradId: null,
  plane: null,
  slot: null,
  profile: null,
  routingRuleCount: 0,
  ready: false,
  lastReceivedAt: null,
});

describe("naming patterns", () => {
  it("expands scid and padded index tokens", () => {
    expect(expandName(pattern("EARENDIL-{scid}"), { scid: 501, n: 1 })).toBe("EARENDIL-501");
    expect(expandName(pattern("B2-{n:03}"), { scid: 501, n: 7 })).toBe("B2-007");
    expect(expandName(pattern("{n}"), { scid: 1, n: 12 })).toBe("12");
  });

  it("rejects unknown tokens and stray braces, and flags patterns without a token", () => {
    expect(parsePattern("SC-{plane}").ok).toBe(false);
    expect(parsePattern("SC-{n:3}").ok).toBe(false);
    expect(parsePattern("SC-{scid").ok).toBe(false);
    expect(parsePattern("  ").ok).toBe(false);
    expect(pattern("FIXED").unique).toBe(false);
  });
});

describe("manifest CSV", () => {
  it("parses quoted fields, CRLF and a BOM, and maps columns by synonym", () => {
    const parsed = parseCsv('﻿Name,SCID,"NORAD id",Plane\r\n"A, one",501,61240,11\r\nB,502,,11\r\n');
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;
    const mapping = guessMapping(parsed.header);
    expect(mapping).toMatchObject({ name: 0, scid: 1, norad: 2, plane: 3, slot: null });
    const rows = readRows(parsed.header, parsed.rows, mapping);
    expect(rows[0]).toMatchObject({ line: 2, name: "A, one", scid: 501, norad: 61240 });
    expect(rows[1]).toMatchObject({ norad: null, problems: [] });
  });

  it("reports bad cells instead of coercing them", () => {
    const parsed = parseCsv("name,scid\nA,5x1\nB,70000\n");
    if (!parsed.ok) throw new Error(parsed.message);
    const rows = readRows(parsed.header, parsed.rows, guessMapping(parsed.header));
    expect(rows.map((r) => r.scid)).toEqual([null, null]);
    expect(rows[0]?.problems[0]?.field).toBe("scid");
  });

  it("rejects an unterminated quote and a header without rows", () => {
    expect(parseCsv('name\n"open').ok).toBe(false);
    expect(parseCsv("name,scid\n").ok).toBe(false);
  });
});

describe("batch", () => {
  it("generates consecutive SCIDs and fills planes", () => {
    const rows = generateRows(pattern("E-{scid}"), 5, 501, { firstPlane: 11, perPlane: 2 });
    expect(rows.map((r) => [r.name, r.plane, r.slot])).toEqual([
      ["E-501", 11, 1],
      ["E-502", 11, 2],
      ["E-503", 12, 1],
      ["E-504", 12, 2],
      ["E-505", 13, 1],
    ]);
    expect(rangeLabel(rows.slice(3))).toBe("E-504 to E-505");
  });

  it("proposes the SCID after the highest existing one", () => {
    expect(nextFreeScid([existing("A", 7), existing("B", null), existing("C", 500)])).toBe(501);
    expect(nextFreeScid([])).toBe(1);
  });

  it("finds clashes within the batch and against the mission", () => {
    const report = checkClashes(generateRows(pattern("E-{n}"), 3, 499, null), [
      existing("e-2", 1),
      existing("Other", 501),
    ]);
    expect(report.clashCount).toBe(2);
    expect(report.rows[1]?.problems).toContain("Name e-2 already exists in this mission");
    expect(report.rows[2]?.problems).toContain("SCID 501 is already Other");
    expect(report.rows[0]?.problems).toEqual([]);
    expect(report.missingNorad).toBe(3);
  });

  it("flags duplicate rows inside a manifest", () => {
    const parsed = parseCsv("name,scid\nA,1\nA,1\n");
    if (!parsed.ok) throw new Error(parsed.message);
    const report = checkClashes(
      manifestRows(readRows(parsed.header, parsed.rows, guessMapping(parsed.header))),
      [],
    );
    expect(report.clashCount).toBe(2);
  });
});
