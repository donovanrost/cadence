import type { GridStackWidget, GridStackOptions } from "gridstack";
import type { Mock } from "vite-plus/test";
import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import EditorLayoutGrid from "./EditorLayoutGrid.vue";
import { editorFixture } from "./fixtures.test-support";
type TestNode = GridStackWidget & { x: number; y: number; el: Element };
type TestGrid = {
  engine: { nodes: TestNode[] };
  setStatic: Mock<(disabled: boolean) => void>;
  destroy: Mock<() => void>;
  load: (nodes: GridStackWidget[]) => void;
  update: (element: Element, changes: GridStackWidget) => void;
  on: (events: string, callback: () => void) => void;
};
const state = vi.hoisted((): { engine: TestGrid | null; handlers: Record<string, () => void> } => ({
  engine: null,
  handlers: {},
}));
vi.mock("gridstack", () => ({
  GridStack: {
    init(_options: GridStackOptions, element: HTMLElement) {
      state.handlers = {};
      const engine: TestGrid = {
        engine: { nodes: [] },
        setStatic: vi.fn<(disabled: boolean) => void>(),
        destroy: vi.fn<() => void>(),
        load(nodes) {
          engine.engine.nodes = nodes.map((node) => ({
            ...node,
            x: node.x ?? 0,
            y: node.y ?? 0,
            el: required(
              Array.from(element.children).find((child) => child.getAttribute("gs-id") === node.id),
            ),
          }));
        },
        update(element, changes) {
          Object.assign(required(engine.engine.nodes.find((node) => node.el === element)), changes);
        },
        on(events, callback) {
          for (const event of events.split(" ")) state.handlers[event] = callback;
        },
      };
      state.engine = engine;
      return engine;
    },
  },
}));
const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
});
function render() {
  const model = editorFixture().model;
  const app = mount(EditorLayoutGrid, {
    props: { placements: model.placements, edits: [], grid: model.grid, disabled: false },
  });
  apps.push(app);
  return app;
}
test("mounting is silent and keyboard movement produces a bounded local draft", async () => {
  const app = render();
  expect(app.emitted("change")).toBeUndefined();
  await app.get('[data-layout-move="battery"]').trigger("keydown", { key: "ArrowRight" });
  expect(app.emitted("change")?.[0]).toEqual([
    [{ placement_id: "battery", x: 1, y: 0, w: 4, h: 2 }],
  ]);
  await app.get('[data-layout-resize="battery"]').trigger("keydown", { key: "ArrowDown" });
  expect(app.emitted("change")?.[1]).toEqual([
    [{ placement_id: "battery", x: 1, y: 0, w: 4, h: 3 }],
  ]);
});
test("drag stops read final neighbor positions and disabling invalidates a queued gesture", async () => {
  const app = render();
  required(state.handlers.dragstart)();
  expect(app.emitted("gesture")?.at(-1)).toEqual([true]);
  required(required(state.engine).engine.nodes[0]).x = 3;
  required(state.handlers.dragstop)();
  await flushPromises();
  expect(app.emitted("change")?.[0]).toEqual([
    [{ placement_id: "battery", x: 3, y: 0, w: 4, h: 2 }],
  ]);
  required(state.handlers.resizestart)();
  required(state.handlers.resizestop)();
  await app.setProps({ disabled: true });
  await flushPromises();
  expect(app.emitted("change")).toHaveLength(1);
  expect(required(state.engine).setStatic).toHaveBeenLastCalledWith(true);
});
test("discard restores saved positions and unmount cancels late emissions", async () => {
  const app = render();
  await app.setProps({ edits: [{ placement_id: "battery", x: 3, y: 2, w: 4, h: 3 }] });
  expect(required(required(state.engine).engine.nodes[0]).x).toBe(3);
  await app.setProps({ edits: [] });
  expect(required(required(state.engine).engine.nodes[0]).x).toBe(0);
  required(state.handlers.dragstart)();
  required(state.handlers.dragstop)();
  app.unmount();
  await flushPromises();
  expect(app.emitted("change")).toBeUndefined();
  expect(required(state.engine).destroy).toHaveBeenCalledOnce();
});
