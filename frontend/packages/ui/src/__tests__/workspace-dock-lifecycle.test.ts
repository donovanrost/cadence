import { createApp, h, nextTick, ref } from "vue";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { required } from "../../../../test-support/required";
import { useWorkspaceDock } from "../useWorkspaceDock";

const unmounts: (() => void)[] = [];
afterEach(() => {
  for (const unmount of unmounts.splice(0)) unmount();
  document.body.replaceChildren();
});

function mountDock() {
  let size = 34;
  let dock: ReturnType<typeof useWorkspaceDock> | undefined;
  const expanded = ref(true);
  const minimize = vi.fn();
  const resize = vi.fn((next: number) => {
    size = next;
    dock?.onResize(next);
  });
  const panel = ref({ getSize: () => size, resize });
  const app = createApp({
    setup() {
      dock = useWorkspaceDock(panel, () => expanded.value, minimize);
      return () => h("div");
    },
  });
  const root = document.createElement("div");
  document.body.append(root);
  app.mount(root);
  let mounted = true;
  const unmount = () => {
    if (mounted) app.unmount();
    mounted = false;
  };
  unmounts.push(unmount);
  return { dock: required(dock), expanded, minimize, resize, unmount };
}

test("unmount cancels a pending snap and restores the persisted height", async () => {
  const { dock, minimize, resize, unmount } = mountDock();
  dock.onDragging(true);
  resize(8);
  expect(dock.snapReady.value).toBe(true);
  unmount();
  expect(resize).toHaveBeenLastCalledWith(34);
  expect(dock.dragging.value).toBe(false);
  resize.mockClear();
  window.dispatchEvent(new MouseEvent("mouseup"));
  window.dispatchEvent(new Event("blur"));
  const escape = new KeyboardEvent("keydown", { key: "Escape", cancelable: true });
  window.dispatchEvent(escape);
  await nextTick();
  expect(escape.defaultPrevented).toBe(false);
  expect(resize).not.toHaveBeenCalled();
  expect(minimize).not.toHaveBeenCalled();
});

test("a queued keyboard collapse cannot update an unmounted workspace", async () => {
  const { resize, minimize, unmount } = mountDock();
  resize(8);
  unmount();
  resize.mockClear();
  await nextTick();
  expect(resize).not.toHaveBeenCalled();
  expect(minimize).not.toHaveBeenCalled();
});

test("controlled dock closure cancels the gesture without emitting another minimize", async () => {
  const { dock, expanded, minimize, resize } = mountDock();
  resize(45);
  dock.onDragging(true);
  resize(8);
  expanded.value = false;
  await nextTick();
  expect(resize).toHaveBeenLastCalledWith(45);
  expect(dock.dragging.value).toBe(false);
  expect(minimize).not.toHaveBeenCalled();
});

test("releasing above the snap threshold retains the smaller shelf height", () => {
  const { dock, minimize, resize } = mountDock();
  dock.onDragging(true);
  resize(16);
  expect(dock.snapReady.value).toBe(false);
  window.dispatchEvent(new MouseEvent("mouseup", { button: 0 }));
  dock.onDragging(false);
  expect(minimize).not.toHaveBeenCalled();
  expect(resize).toHaveBeenLastCalledWith(16);
  dock.onDragging(true);
  resize(8);
  dock.cancelDrag();
  expect(resize).toHaveBeenLastCalledWith(16);
});
