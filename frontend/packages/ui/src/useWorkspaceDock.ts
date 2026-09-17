import { onBeforeUnmount, ref, watch, type Ref } from "vue";

export const workspaceDockSnapThreshold = 11;
export const workspaceDockDefaultSize = 34;

interface DockPanel {
  getSize(): number | undefined;
  resize(size: number): void;
}

interface DockDrag {
  size: number;
  release: "pending" | "commit" | "cancel";
}

/** Reka resizes continuously; the workspace arms a threshold and minimizes on release. */
export function useWorkspaceDock(
  panel: Ref<DockPanel | undefined>,
  expanded: () => boolean,
  minimize: () => void,
) {
  const dragging = ref(false);
  const snapReady = ref(false);
  let drag: DockDrag | undefined;
  let expandedSize = workspaceDockDefaultSize;
  let disposed = false;

  function onResize(size: number) {
    snapReady.value = size <= workspaceDockSnapThreshold;
    if (drag) return;
    if (!snapReady.value) {
      expandedSize = size;
      return;
    }
    // Keyboard resizing can cross the same threshold. Wait for Reka's resize callbacks.
    queueMicrotask(() => {
      const size = panel.value?.getSize();
      if (
        disposed ||
        drag ||
        !expanded() ||
        size === undefined ||
        size > workspaceDockSnapThreshold
      )
        return;
      panel.value?.resize(expandedSize);
      minimize();
    });
  }

  function releaseMouse(event: MouseEvent) {
    if (drag && drag.release !== "cancel" && event.button === 0) drag.release = "commit";
  }

  function releaseTouch(event: TouchEvent) {
    if (drag && drag.release !== "cancel" && event.touches.length === 0) drag.release = "commit";
  }

  function cancelDrag() {
    if (!drag) return;
    drag.release = "cancel";
    // Reka listens for mouseup, but not Escape or window blur. End its active gesture
    // before restoring the panel; re-registering the handle here would lose its release.
    window.dispatchEvent(new MouseEvent("mouseup"));
    onDragging(false);
  }

  function onKeyDown(event: KeyboardEvent) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    cancelDrag();
  }

  function listen() {
    window.addEventListener("mouseup", releaseMouse, true);
    window.addEventListener("touchend", releaseTouch, true);
    window.addEventListener("touchcancel", cancelDrag, true);
    window.addEventListener("contextmenu", cancelDrag, true);
    window.addEventListener("blur", cancelDrag);
    window.addEventListener("keydown", onKeyDown, true);
  }

  function unlisten() {
    window.removeEventListener("mouseup", releaseMouse, true);
    window.removeEventListener("touchend", releaseTouch, true);
    window.removeEventListener("touchcancel", cancelDrag, true);
    window.removeEventListener("contextmenu", cancelDrag, true);
    window.removeEventListener("blur", cancelDrag);
    window.removeEventListener("keydown", onKeyDown, true);
  }

  function onDragging(active: boolean) {
    if (active) {
      if (drag || !expanded() || disposed) return;
      drag = { size: panel.value?.getSize() || expandedSize, release: "pending" };
      dragging.value = true;
      listen();
      return;
    }
    if (!drag) return;
    const finished = drag;
    const shouldMinimize = finished.release === "commit" && snapReady.value;
    drag = undefined;
    dragging.value = false;
    unlisten();
    if (shouldMinimize || finished.release !== "commit") panel.value?.resize(finished.size);
    else expandedSize = panel.value?.getSize() || expandedSize;
    if (shouldMinimize) minimize();
  }

  watch(expanded, (visible) => {
    if (!visible) cancelDrag();
  });
  onBeforeUnmount(() => {
    disposed = true;
    cancelDrag();
  });

  return { dragging, snapReady, onDragging, onResize, cancelDrag };
}
