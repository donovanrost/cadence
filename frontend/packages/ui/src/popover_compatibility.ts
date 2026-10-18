export const CADENCE_OVERLAY_OPENED_EVENT = "cadence:overlay-opened";

export function announceCadencePopoverOpened(
  windowObject: Window & typeof globalThis,
  rootElement: HTMLElement,
) {
  windowObject.dispatchEvent(
    new windowObject.CustomEvent(CADENCE_OVERLAY_OPENED_EVENT, { detail: rootElement }),
  );
}

export function subscribeToLegacyOverlayOpen(
  windowObject: Window & typeof globalThis,
  rootElement: HTMLElement,
  close: () => void,
) {
  const onOverlayOpened = (event: Event) => {
    if (!(event instanceof windowObject.CustomEvent)) return;
    const openedRoot: unknown = event.detail;
    if (!(openedRoot instanceof windowObject.Node)) return;
    if (openedRoot !== rootElement && !rootElement?.contains?.(openedRoot)) close();
  };

  windowObject.addEventListener(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened);

  return () => {
    windowObject.removeEventListener(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened);
  };
}

export function preservesPopoverOpenState(
  open: boolean,
  previousIdentity: string | null | undefined,
  nextIdentity: string | null | undefined,
) {
  return Boolean(open && nextIdentity && previousIdentity === nextIdentity);
}

export function focusCurrentPopoverTrigger(rootElement: HTMLElement | null) {
  const trigger = rootElement?.querySelector<HTMLElement>(":scope > [data-overlay-trigger]");
  if (!trigger || typeof trigger.focus !== "function") return false;

  trigger.focus();
  return true;
}
