export declare const CADENCE_OVERLAY_OPENED_EVENT: string;

export declare function announceCadencePopoverOpened(
  windowObject: { CustomEvent: typeof CustomEvent; dispatchEvent(event: Event): boolean },
  rootElement: Element | null,
): void;

export declare function subscribeToLegacyOverlayOpen(
  windowObject: Window,
  rootElement: Element | null,
  close: () => void,
): () => void;

export declare function preservesPopoverOpenState(
  open: boolean,
  previousIdentity: string | null | undefined,
  nextIdentity: string | null | undefined,
): boolean;

export declare function focusCurrentPopoverTrigger(rootElement: Element | null): boolean;
