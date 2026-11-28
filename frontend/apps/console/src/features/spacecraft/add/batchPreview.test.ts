import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { ProposedSpacecraft } from "./batch.ts";
import BatchPreview from "./BatchPreview.vue";

/** Synthetic batch rows (rule 5, #308 follow-up), not from a real manifest. */
const row = (key: string, o: Partial<ProposedSpacecraft> = {}): ProposedSpacecraft => ({
  key,
  name: "EARENDIL-501",
  scid: 501,
  norad: 70_001,
  plane: 1,
  slot: 1,
  profileName: null,
  problems: [],
  ...o,
});

describe("A3 Batch preview words (rule 5)", () => {
  it("reads a blank name as Unnamed and a missing SCID as not set, never a dash", () => {
    const w = mount(BatchPreview, {
      props: { rows: [row("a"), row("b", { name: "  ", scid: null, norad: null })] },
    });
    const cells = (i: number) =>
      w
        .findAll("tbody tr")
        .at(i)
        ?.findAll("td")
        .map((c) => c.text());
    expect(cells(0)?.slice(0, 3)).toEqual(["EARENDIL-501", "501", "70001"]);
    expect(cells(1)?.slice(0, 3)).toEqual(["Unnamed", "not set", "not set"]);
    expect(w.text()).not.toContain("—");
  });
});
