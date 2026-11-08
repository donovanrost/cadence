import type { ApiError } from "./http.ts";

/** Screen data lifecycle. `receivedAt` lets the UI show freshness and mark stale data. */
export type RemoteState<T> =
  | { status: "loading" }
  | { status: "ready"; value: T; receivedAt: Date }
  | { status: "failed"; error: ApiError };
