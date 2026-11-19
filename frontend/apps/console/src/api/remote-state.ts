import type { ApiError } from "./http.ts";

/**
 * Screen data lifecycle. `receivedAt` lets the UI show freshness and mark stale data.
 * `requestedAt` (useRemoteQuery): when this value's request started, so a screen can tell a read
 * asked for after some event from one already in flight then (#395). Absent: not known.
 */
export type RemoteState<T> =
  | { status: "loading" }
  | { status: "ready"; value: T; receivedAt: Date; requestedAt?: Date }
  | { status: "failed"; error: ApiError };
