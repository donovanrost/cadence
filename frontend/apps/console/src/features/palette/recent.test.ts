import { afterEach, describe, expect, it } from "vite-plus/test";
import { RECENT_MAX, recentItems, rememberOpened } from "./recent.ts";
import { grouped, SETUP_GROUPS, type PaletteItem } from "./results.ts";

const item = (key: string, group: PaletteItem["group"] = "Spacecraft"): PaletteItem => ({
  key,
  group,
  title: key.toUpperCase(),
  subtitle: "sub",
  hint: "HINT",
  state: null,
  to: { name: "ops.now", query: { k: key } },
  commandTo: null,
  rank: 0,
});
const always = () => true;

describe("palette Recent", () => {
  afterEach(() => localStorage.clear());

  it("keeps the last 5 opened per mission, newest first, without duplicates", () => {
    for (const k of ["a", "b", "c", "d", "e", "f", "b"]) rememberOpened("m1", item(k));
    const recent = recentItems("m1", always);
    expect(recent).toHaveLength(RECENT_MAX);
    expect(recent.map((r) => r.title)).toEqual(["B", "F", "E", "D", "C"]);
    expect(recent[0]).toMatchObject({ group: "Recent", key: "recent-b", commandTo: null });
    expect(recentItems("m2", always)).toEqual([]);
  });

  it("re-opening a recent row doesn't nest its key, and dead routes drop out", () => {
    rememberOpened("m1", item("a"));
    const [first] = recentItems("m1", always);
    if (first) rememberOpened("m1", first);
    expect(recentItems("m1", always).map((r) => r.key)).toEqual(["recent-a"]);
    expect(recentItems("m1", () => false)).toEqual([]);
  });

  it("reads garbage in storage as nothing", () => {
    localStorage.setItem("apogee.palette.recent.m1", '[{"key":1},"x",{}]');
    expect(recentItems("m1", always)).toEqual([]);
    localStorage.setItem("apogee.palette.recent.m1", "{not json");
    expect(recentItems("m1", always)).toEqual([]);
  });
});

describe("palette Setup-mode ranking", () => {
  it("puts Profiles, Stations and Pages ahead of Spacecraft in Setup", () => {
    const items = [item("sc"), item("pg", "Pages"), item("pr", "Profiles"), item("r", "Recent")];
    expect(grouped(items, new Set()).map((g) => g.group)).toEqual([
      "Recent",
      "Spacecraft",
      "Profiles",
      "Pages",
    ]);
    expect(grouped(items, new Set(), SETUP_GROUPS).map((g) => g.group)).toEqual([
      "Recent",
      "Profiles",
      "Pages",
      "Spacecraft",
    ]);
  });
});
