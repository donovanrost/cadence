import { GridStack } from "gridstack";
import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { nextTick } from "vue";
import DashboardCanvas from "./DashboardCanvas.vue";
import { workspaceFixture } from "./fixtures.test-support";
let app: Pick<ReturnType<typeof mount>, "emitted" | "get" | "setProps" | "unmount">;
afterEach(() => {
  app?.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});
test("real canvas/grid/widgets preserve native identity, disclosure and updated values", async () => {
  app = mount(DashboardCanvas, {
    props: { presentation: workspaceFixture() },
    attachTo: document.body,
  });
  const grid = app.get("#workspace-grid").element,
    widget = app.get("#battery-widget").element;
  expect(app.get('[data-value="voltage"]').text()).toBe("28.4");
  await app.get("#power-section-trigger").trigger("click");
  await flushPromises();
  expect(app.get("#power-section-trigger").attributes("aria-expanded")).toBe("false");
  const next = workspaceFixture();
  required(
    required(next.groups[0]).grid.widgets[0],
  ).presentation.body.content.presentation.value.text = "29.1";
  await app.setProps({ presentation: next });
  await flushPromises();
  expect(app.get("#workspace-grid").element).toBe(grid);
  expect(app.get("#battery-widget").element).toBe(widget);
  expect(app.get('[data-value="voltage"]').text()).toBe("29.1");
  expect(app.get("#power-section-trigger").attributes("aria-expanded")).toBe("false");
});
test("real GridStack emits layout changes only in edit mode and disposes timers", async () => {
  vi.useFakeTimers();
  const presentation = workspaceFixture();
  app = mount(DashboardCanvas, { props: { presentation }, attachTo: document.body });
  const element = app.get("#workspace-grid").element;
  if (!("gridstack" in element) || !(element.gridstack instanceof GridStack))
    throw Error("Expected a mounted grid");
  const grid = element.gridstack;
  grid.update(app.get<HTMLElement>("#battery-widget").element, { x: 2, y: 0, w: 4, h: 2 });
  await vi.advanceTimersByTimeAsync(500);
  expect(app.emitted("layout_changed")).toBeUndefined();
  const editing = workspaceFixture();
  required(editing.groups[0]).grid.controller.props.edit_mode = true;
  await app.setProps({ presentation: editing });
  await nextTick();
  grid.update(app.get<HTMLElement>("#battery-widget").element, { x: 3, y: 0, w: 5, h: 2 });
  await vi.advanceTimersByTimeAsync(500);
  expect(app.emitted("layout_changed")?.at(-1)?.[0]).toEqual({
    layouts: [{ widget_id: "battery", x: 3, y: 0, w: 5, h: 2 }],
  });
  app.unmount();
  await vi.advanceTimersByTimeAsync(500);
});
