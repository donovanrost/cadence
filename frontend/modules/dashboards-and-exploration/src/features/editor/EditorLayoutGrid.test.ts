import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import EditorLayoutGrid from "./EditorLayoutGrid.vue";
import { editorFixture } from "./fixtures.test-support";
const state = vi.hoisted(() => ({ engine: null as any, handlers: {} as Record<string, Function> }));
vi.mock("gridstack", () => ({
  GridStack: {
    init(_options: any, element: HTMLElement) {
      state.handlers = {};
      const engine = {
        engine: { nodes: [] as any[] },
        setStatic: vi.fn(),
        destroy: vi.fn(),
        load(nodes: any[]) {
          engine.engine.nodes = nodes.map((n) => ({
            ...n,
            x: n.x ?? 0,
            y: n.y ?? 0,
            el: Array.from(element.children).find((e: any) => e.getAttribute("gs-id") === n.id),
          }));
        },
        update(el: any, changes: any) {
          Object.assign(
            engine.engine.nodes.find((n) => n.el === el),
            changes,
          );
        },
        on(events: string, fn: Function) {
          for (const event of events.split(" ")) state.handlers[event] = fn;
        },
      };
      state.engine = engine;
      return engine;
    },
  },
}));
const apps: ReturnType<typeof mount>[] = [];
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
  state.handlers.dragstart();
  expect(app.emitted("gesture")?.at(-1)).toEqual([true]);
  state.engine.engine.nodes[0].x = 3;
  state.handlers.dragstop();
  await flushPromises();
  expect(app.emitted("change")?.[0]).toEqual([
    [{ placement_id: "battery", x: 3, y: 0, w: 4, h: 2 }],
  ]);
  state.handlers.resizestart();
  state.handlers.resizestop();
  await app.setProps({ disabled: true });
  await flushPromises();
  expect(app.emitted("change")).toHaveLength(1);
  expect(state.engine.setStatic).toHaveBeenLastCalledWith(true);
});
test("discard restores saved positions and unmount cancels late emissions", async () => {
  const app = render();
  await app.setProps({ edits: [{ placement_id: "battery", x: 3, y: 2, w: 4, h: 3 }] });
  expect(state.engine.engine.nodes[0].x).toBe(3);
  await app.setProps({ edits: [] });
  expect(state.engine.engine.nodes[0].x).toBe(0);
  state.handlers.dragstart();
  state.handlers.dragstop();
  app.unmount();
  await flushPromises();
  expect(app.emitted("change")).toBeUndefined();
  expect(state.engine.destroy).toHaveBeenCalledOnce();
});
