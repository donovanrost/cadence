import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { layoutEdits, mergeLayoutEdits } from "./layout-draft";
import { editorFixture } from "./fixtures.test-support";
test("layout snapshots retain every authored placement including moved neighbors", () => {
  const first = required(editorFixture().model.placements[0]);
  const second = { ...first, id: "neighbor" };
  const nodes = [
    { id: first.id, x: 2, y: 0, w: 4, h: 2 },
    { id: second.id, x: 2, y: 2, w: 4, h: 2 },
  ];
  expect(layoutEdits(nodes, [first, second])).toEqual(
    nodes.map(({ id, ...layout }) => ({ placement_id: id, ...layout })),
  );
});
test("layout drafts reject incomplete, duplicate, foreign, non-integer and out-of-bounds nodes", () => {
  const placements = editorFixture().model.placements;
  const node = { id: "battery", x: 0, y: 0, w: 4, h: 2 };
  for (const nodes of [
    [],
    [node, node],
    [{ ...node, id: "other" }],
    [{ ...node, x: 10 }],
    [{ ...node, y: 24 }],
    [{ ...node, w: 1 }],
    [{ ...node, h: 25 }],
    [{ ...node, x: 0.5 }],
    [{ ...node, y: NaN }],
  ])
    expect(() => layoutEdits(nodes, placements)).toThrow();
});
test("updates from one section preserve the other section's pending layout", () => {
  const first = { placement_id: "a", x: 1, y: 0, w: 4, h: 2 };
  const second = { ...first, placement_id: "b" };
  expect(mergeLayoutEdits([first, second], [{ ...first, x: 2 }])).toEqual([
    { ...first, x: 2 },
    second,
  ]);
});
