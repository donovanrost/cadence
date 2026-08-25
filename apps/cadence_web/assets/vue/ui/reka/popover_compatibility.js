export const CADENCE_OVERLAY_OPENED_EVENT = "cadence:overlay-opened"

export function announceCadencePopoverOpened(windowObject, rootElement) {
  windowObject.dispatchEvent(
    new windowObject.CustomEvent(CADENCE_OVERLAY_OPENED_EVENT, {detail: rootElement}),
  )
}

export function subscribeToLegacyOverlayOpen(windowObject, rootElement, close) {
  const onOverlayOpened = (event) => {
    if (event.detail !== rootElement) close()
  }

  windowObject.addEventListener(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened)

  return () => {
    windowObject.removeEventListener(CADENCE_OVERLAY_OPENED_EVENT, onOverlayOpened)
  }
}

export function preservesPopoverOpenState(open, previousIdentity, nextIdentity) {
  return Boolean(open && nextIdentity && previousIdentity === nextIdentity)
}
