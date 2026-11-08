import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { grouped, parseQuery, PER_GROUP, search } from "./results.ts";

const fleet = Array.from({ length: 500 }, (_, i) => spacecraftRow(i + 1));
const pages = [
  { name: "ops.now", title: "Now", mode: "ops" },
  { name: "ops.contacts", title: "Contacts", mode: "ops" },
];

describe("palette search", () => {
  it("puts the exact SCID first for numeric queries", () => {
    const items = search("312", fleet, pages);
    expect(items[0]?.title).toBe("EARENDIL-312");
    expect(items[0]?.hint).toBe("SCID 312");
    expect(items[0]?.commandTo).toEqual({
      name: "ops.commands.new",
      query: { targets: "sc:spacecraft-earendil-312" },
    });
  });

  it("offers 'Command …' for a narrow spacecraft match", () => {
    const actions = search("312", fleet, pages).filter((i) => i.group === "Actions");
    expect(actions.map((a) => a.title)).toEqual(["Command EARENDIL-312…"]);
  });

  it("shows pages (not spacecraft) for an empty query", () => {
    expect(search("", fleet, pages).map((i) => i.group)).toEqual(["Pages", "Pages"]);
  });

  it("honours prefixes and finds pages by title", () => {
    expect(parseQuery("# 31")).toEqual({ text: "31", only: "spacecraft" });
    expect(search("#contacts", fleet, pages)).toEqual([]);
    expect(search(">set_", fleet, pages)).toEqual([]);
    expect(search("cont", fleet, pages).map((i) => i.title)).toEqual(["Contacts"]);
  });

  it("caps groups at five rows unless expanded", () => {
    const items = search("earendil", fleet, pages);
    const [first] = grouped(items, new Set());
    expect(first?.items).toHaveLength(PER_GROUP);
    expect(first?.more).toBe(500 - PER_GROUP);
    expect(grouped(items, new Set(["Spacecraft"]))[0]?.items).toHaveLength(500);
  });
});
