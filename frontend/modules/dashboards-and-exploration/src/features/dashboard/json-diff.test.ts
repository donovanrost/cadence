import { expect, test } from "vite-plus/test";
import { lineDiff } from "./json-diff";

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
