import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { scid as scidReader } from "@/api/index.ts";
import { readRecent, remember, suggest } from "./recent.ts";

const r = (scid: number, point: string) => ({ scid: scidReader(scid), name: `SC-${scid}`, point });
const sel = (scids: number[], points: string[]) => ({
  scids: scids.map((n) => scidReader(n)),
  points,
  window: { kind: "preset" as const, key: "6h" as const },
});

describe("Explore suggestions (OpsLists §Telemetry empty state)", () => {
  afterEach(() => vi.unstubAllGlobals());
  it("keeps the newest first, once each, and suggests three not plotted now", () => {
    const list = remember([r(1, "A"), r(2, "B")], [r(2, "B"), r(3, "C")]);
    expect(list.map((x) => `${x.scid}${x.point}`)).toEqual(["2B", "3C", "1A"]);
    const more = remember(list, [r(4, "D")]);
    expect(suggest(more, sel([], [])).map((x) => x.point)).toEqual(["D", "B", "C"]);
    expect(suggest(more, sel([4], ["D"])).map((x) => x.point)).toEqual(["B", "C", "A"]);
  });
  it("reads nothing when storage is blocked or holds junk", () => {
    vi.stubGlobal("localStorage", {
      getItem: () => {
        throw new Error("blocked");
      },
    });
    expect(readRecent("m")).toEqual([]);
    vi.stubGlobal("localStorage", {
      getItem: () => '[{"scid":"x"},{"scid":1,"name":"A","point":"P"}]',
    });
    expect(readRecent("m")).toEqual([{ scid: 1, name: "A", point: "P" }]);
  });
});
