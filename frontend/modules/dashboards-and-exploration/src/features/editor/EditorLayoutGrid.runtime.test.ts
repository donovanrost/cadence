import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { GridStack, type GridHTMLElement } from "gridstack";
import EditorLayoutGrid from "./EditorLayoutGrid.vue";
import { editorFixture } from "./fixtures.test-support";

let app: Pick<ReturnType<typeof mount>, "emitted" | "get" | "setProps" | "unmount"> | undefined;
afterEach(() => {
  app?.unmount();
  app = undefined;
  vi.restoreAllMocks();
});

test("the installed GridStack supports editor movement, resize, discard and disposal", async () => {
  const model = editorFixture().model;
  app = mount(EditorLayoutGrid, {
    props: { placements: model.placements, edits: [], grid: model.grid, disabled: false },
    attachTo: document.body,
  });
  const element = app.get(".editor-authoring-grid").element as GridHTMLElement;
  const grid = required(element.gridstack);
  const widget = app.get('[gs-id="battery"]').element;
  expect(grid).toBeInstanceOf(GridStack);
  expect(grid.opts.column).toBe(model.grid.columns);
  expect(grid.opts.cellHeight).toBe(model.grid.row_height_px);
  expect(app.emitted("change")).toBeUndefined();

  await app.get('[data-layout-move="battery"]').trigger("keydown", { key: "ArrowRight" });
  expect(app.emitted("change")?.at(-1)).toEqual([
    [{ placement_id: "battery", x: 1, y: 0, w: 4, h: 2 }],
  ]);
  await app.get('[data-layout-resize="battery"]').trigger("keydown", { key: "ArrowDown" });
  expect(app.emitted("change")?.at(-1)).toEqual([
    [{ placement_id: "battery", x: 1, y: 0, w: 4, h: 3 }],
  ]);

  await app.setProps({ edits: [{ placement_id: "battery", x: 3, y: 2, w: 4, h: 3 }] });
  expect(grid.engine.nodes[0]).toMatchObject({ x: 3, y: 2, w: 4, h: 3 });
  await app.setProps({ edits: [] });
  expect(grid.engine.nodes[0]).toMatchObject(required(model.placements[0]).layout);
  expect(app.get('[gs-id="battery"]').element).toBe(widget);

  await app.setProps({ disabled: true });
  expect(grid.opts.staticGrid).toBe(true);
  await app.get('[data-layout-move="battery"]').trigger("keydown", { key: "ArrowRight" });
  expect(app.emitted("change")).toHaveLength(2);

  const destroy = vi.spyOn(grid, "destroy");
  app.unmount();
  app = undefined;
  await flushPromises();
  expect(destroy).toHaveBeenCalledExactlyOnceWith(false);
  expect(element.gridstack).toBeUndefined();
});
