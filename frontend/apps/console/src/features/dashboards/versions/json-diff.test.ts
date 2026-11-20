import { describe, expect, it, test } from "vite-plus/test";
import type { VersionChange } from "../editor/contracts.ts";
import { lineDiff } from "./json-diff.ts";
import { compareSentence } from "./useVersions.ts";

test("marks added and removed lines and collapses distant unchanged lines", () => {
  const before = [
    "{",
    ...Array.from({ length: 10 }, (_, i) => `  "k${i}": ${i},`),
    '  "title": "Old"',
    "}",
  ].join("\n");
  const after = before.replace('"Old"', '"New"');
  const diff = lineDiff(before, after, 2);
  expect(diff.filter((l) => l.kind === "removed").map((l) => "text" in l && l.text)).toEqual([
    '  "title": "Old"',
  ]);
  expect(diff.filter((l) => l.kind === "added").map((l) => "text" in l && l.text)).toEqual([
    '  "title": "New"',
  ]);
  expect(diff[0]).toEqual({ kind: "gap", hidden: 9 });
});

test("identical texts collapse to a single gap", () => {
  expect(lineDiff("a\nb\nc", "a\nb\nc", 0)).toEqual([{ kind: "gap", hidden: 3 }]);
});

describe("compare outcome (B6, #245)", () => {
  it("says the version pair and the change count, or that they're the same", () => {
    const change = {} as VersionChange;
    expect(compareSentence({ from: 3, to: 5, changes: [] })).toBe(
      "v3 to v5: these versions are the same.",
    );
    expect(compareSentence({ from: 3, to: 5, changes: [change] })).toBe("v3 to v5: 1 change.");
    expect(compareSentence({ from: 1, to: 2, changes: [change, change] })).toBe(
      "v1 to v2: 2 changes.",
    );
  });
});
