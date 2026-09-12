const SNAP_WIDTH = 140;
const MAX_WIDTH = 480;
const MIN_CANVAS_WIDTH = 360;
const COORDINATED_BREAKPOINT = 1100;

export const createNavRailController = ({
  el,
  windowObject = window,
  documentObject = document,
  storage = windowObject.localStorage,
}) => {
  const storageKey = el.dataset.storageKey || "cadence-ops-rail";
  let handle = null;
  let expanded = false;
  let width = null;
  let mounted = false;
  let activeDrag = null;

  const readState = () => {
    const stored = storage.getItem(storageKey);
    const defaultExpanded = el.hasAttribute("data-default-expanded");
    width = null;

    if (!stored) {
      expanded = defaultExpanded;
      return;
    }

    try {
      const parsed = JSON.parse(stored);
      expanded = parsed.state === "expanded";
      if (Number.isFinite(parsed.width)) width = parsed.width;
    } catch (_error) {
      expanded = stored === "expanded";
    }
  };

  const persist = () => {
    storage.setItem(
      storageKey,
      JSON.stringify({ state: expanded ? "expanded" : "collapsed", width }),
    );
  };

  const apply = () => {
    if (expanded) {
      el.setAttribute("data-expanded", "");

      const peerWidth = Array.from(documentObject.querySelectorAll("[data-rail-role]"))
        .filter((rail) => rail !== el)
        .reduce((total, rail) => total + rail.getBoundingClientRect().width, 0);
      const available = Math.max(
        SNAP_WIDTH,
        windowObject.innerWidth - peerWidth - MIN_CANVAS_WIDTH,
      );
      const defaultWidth = el.dataset.railRole === "context" ? 288 : 224;
      const preferredWidth = handle && width ? width : defaultWidth;
      const appliedWidth = Math.min(preferredWidth, available, MAX_WIDTH);

      el.style.width = appliedWidth < preferredWidth || width ? `${appliedWidth}px` : "";
    } else {
      el.removeAttribute("data-expanded");
      el.style.width = "";
    }
  };

  const onViewportResize = () => apply();

  const onPeerExpanded = (event) => {
    if (event.detail !== el && windowObject.innerWidth < COORDINATED_BREAKPOINT && expanded) {
      expanded = false;
      persist();
      apply();
    }
  };

  const onClick = (event) => {
    if (!event.target.closest("[data-rail-toggle]")) return;

    expanded = !expanded;
    persist();
    apply();

    if (expanded) {
      windowObject.dispatchEvent(
        new windowObject.CustomEvent("cadence:rail-expanded", { detail: el }),
      );
    }
  };

  const finishDrag = () => {
    if (!activeDrag) return;

    const { move, up, previousTransition, startWidth } = activeDrag;
    windowObject.removeEventListener("pointermove", move);
    windowObject.removeEventListener("pointerup", up);
    windowObject.removeEventListener("pointercancel", up);
    el.style.transition = previousTransition;

    if (!expanded && startWidth >= SNAP_WIDTH) width = Math.round(startWidth);

    activeDrag = null;
    persist();
  };

  const onPointerDown = (event) => {
    event.preventDefault();

    try {
      handle.setPointerCapture(event.pointerId);
    } catch (_error) {
      // Synthetic events can lack an active pointer; window listeners still cover the drag.
    }

    const startX = event.clientX;
    const startWidth = el.getBoundingClientRect().width;
    const previousTransition = el.style.transition;
    el.style.transition = "none";

    const move = (moveEvent) => {
      const raw = startWidth + (startX - moveEvent.clientX);
      expanded = raw >= SNAP_WIDTH;

      if (expanded) width = Math.min(Math.round(raw), MAX_WIDTH);

      apply();
    };

    const up = () => finishDrag();
    activeDrag = { move, up, previousTransition, startWidth };

    windowObject.addEventListener("pointermove", move);
    windowObject.addEventListener("pointerup", up, { once: true });
    windowObject.addEventListener("pointercancel", up, { once: true });
  };

  const bindHandle = () => {
    const nextHandle = el.querySelector("[data-rail-resize]");

    if (nextHandle === handle) return;
    if (handle) handle.removeEventListener("pointerdown", onPointerDown);

    handle = nextHandle;
    if (handle) handle.addEventListener("pointerdown", onPointerDown);
  };

  const mount = () => {
    if (mounted) return;

    mounted = true;
    bindHandle();
    readState();
    apply();
    windowObject.addEventListener("resize", onViewportResize);
    windowObject.addEventListener("cadence:rail-expanded", onPeerExpanded);
    el.addEventListener("click", onClick);
  };

  const update = () => {
    bindHandle();
    apply();
  };

  const destroy = () => {
    if (!mounted) return;

    if (activeDrag) finishDrag();
    if (handle) handle.removeEventListener("pointerdown", onPointerDown);
    windowObject.removeEventListener("resize", onViewportResize);
    windowObject.removeEventListener("cadence:rail-expanded", onPeerExpanded);
    el.removeEventListener("click", onClick);
    mounted = false;
  };

  const state = () => ({ expanded, width });

  return { mount, update, destroy, state };
};
