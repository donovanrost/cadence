/** A host page carries a sequenced operation ledger and supports recovery by reading it. */
export type PageSnapshotProtocol = {
  protocol: "page-snapshot";
  actorId: string;
  guardNavigation?: (canLeave: () => boolean) => () => void;
};

/** A remote query returns domain evidence and a transport completion receipt. */
export type RemoteQueryProtocol = { protocol: "remote-query" };
export type WorkflowProtocol = PageSnapshotProtocol | RemoteQueryProtocol;

export const validReviewReason = (reason: string): boolean =>
  reason.trim().length > 0 && new TextEncoder().encode(reason.trim()).length <= 4096;
