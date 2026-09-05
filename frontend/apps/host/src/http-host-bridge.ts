import type {
  HostJsonValue,
  CatalogApplication,
  HostActionReceipt,
  HostActionRequest,
  HostActivityEvent,
  HostActivityListener,
  HostBridge,
  HostContext,
  HostQueryRequest,
  HostSessionDescriptor,
  HostQueryParams,
} from "@cadence/plugin-sdk";
import { assertHostQueryParams } from "@cadence/plugin-sdk";

interface HostProblem {
  schema: "cadence.application-host-problem.v1";
  code: string;
  message: string;
}

export interface BridgeOptions {
  fetch?: typeof globalThis.fetch;
  requestTimeoutMs?: number;
  onSessionFailure?: (operation: HostActivityEvent["kind"], error: HostBridgeError) => void;
  /** Captured by Phoenix; never read from an individual remote request. */
  queryParams?: HostQueryParams;
}

export type CallerActionRequest<TInput = unknown> = HostActionRequest<TInput> & {
  idempotencyKey?: string;
};

export interface HttpHostBridge extends HostBridge {
  invalidate(): void;
}

export class HostBridgeError extends Error {
  readonly code: string;
  readonly status: number;
  readonly referenceId: string;

  constructor(status: number, code: string, message: string, referenceId = referenceIdFor()) {
    super(`${message} Reference ID: ${referenceId}.`);
    this.name = "HostBridgeError";
    this.status = status;
    this.code = code;
    this.referenceId = referenceId;
  }
}

export function createHttpHostBridge(
  session: HostSessionDescriptor,
  application: CatalogApplication,
  options: BridgeOptions = {},
): HttpHostBridge {
  const fetcher = options.fetch ?? globalThis.fetch;
  const requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
  const listeners = new Set<HostActivityListener>();
  const inFlightControllers = new Set<AbortController>();
  const queryParams = snapshotQueryParams(options.queryParams ?? {});
  let active = true;

  if (!Number.isFinite(requestTimeoutMs) || requestTimeoutMs <= 0) {
    throw new Error("The host bridge request timeout must be positive and finite.");
  }

  function publish(event: HostActivityEvent): void {
    for (const listener of listeners) listener(event);
  }

  async function withActivity<TResult>(
    kind: HostActivityEvent["kind"],
    contractId: string,
    operation: () => Promise<TResult>,
  ): Promise<TResult> {
    assertBridgeActive();
    publish(activityEvent(kind, contractId, "started"));

    try {
      assertBridgeActive();
      const result = await operation();
      assertBridgeActive();
      publish(activityEvent(kind, contractId, "completed"));
      assertBridgeActive();
      return result;
    } catch (error) {
      if (!active) throw staleContextError();
      publish(activityEvent(kind, contractId, "failed"));
      throw error;
    }
  }

  async function request<TResult>(
    operation: HostActivityEvent["kind"],
    path: string,
    body: unknown,
    idempotencyKey?: string,
  ): Promise<TResult> {
    assertBridgeActive();

    const controller = new AbortController();
    inFlightControllers.add(controller);
    const deadlineTimer = setTimeout(
      () => controller.abort(requestTimedOutError()),
      requestTimeoutMs,
    );

    try {
      assertBridgeActive();
      let response: Response;
      try {
        response = await raceWithAbort(
          Promise.resolve().then(() =>
            fetcher(`${session.bridgeBaseUrl}/${path}`, {
              method: "POST",
              credentials: "same-origin",
              headers: {
                "content-type": "application/json",
                "x-cadence-poc-session": session.sessionId,
                "x-csrf-token": session.csrfToken,
                ...(idempotencyKey !== undefined ? { "idempotency-key": idempotencyKey } : {}),
              },
              body: JSON.stringify(body),
              signal: controller.signal,
            }),
          ),
          controller.signal,
          () => (active ? requestTimedOutError() : staleContextError()),
        );
      } catch (error) {
        if (!active) throw staleContextError();
        if (isRequestControlError(error)) throw error;
        throw new HostBridgeError(
          0,
          "transport_failed",
          "The host request could not be completed.",
        );
      }

      assertBridgeActive();
      let payload: unknown;
      try {
        payload = await raceWithAbort(
          Promise.resolve().then(() => response.json()),
          controller.signal,
          () => (active ? requestTimedOutError() : staleContextError()),
        );
      } catch (error) {
        if (!active) throw staleContextError();
        if (isRequestControlError(error)) throw error;
        if (response.ok) throw invalidResponseFor(response.status, operation);
        payload = undefined;
      }

      assertBridgeActive();
      if (!response.ok) throw problemFor(response.status, payload);
      assertBridgeActive();
      return payload as TResult;
    } finally {
      clearTimeout(deadlineTimer);
      inFlightControllers.delete(controller);
    }
  }

  return {
    async query<TResult>(query: HostQueryRequest): Promise<TResult> {
      assertBridgeActive();
      assertActiveContext(query.context, session.context);
      assertSelectedQuery(query, application);

      try {
        return await withActivity("query", query.queryId, () =>
          request<TResult>("query", "query", {
            applicationKey: application.applicationKey,
            applicationVersion: application.applicationVersion,
            surfaceId: application.surface.surfaceId,
            surfaceVersion: application.surface.version,
            queryId: query.queryId,
            queryVersion: query.version,
            scope: scopeFrom(session.context),
            params: queryParams,
          }),
        );
      } catch (error) {
        notifySessionFailure("query", error);
        throw error;
      }
    },

    async execute<TInput, TResult>(
      action: CallerActionRequest<TInput>,
    ): Promise<HostActionReceipt<TResult>> {
      assertBridgeActive();
      assertActiveContext(action.context, session.context);
      assertSelectedAction(action, application);
      // The caller key is the frontend retry contract. The authoritative
      // backend provider must still deduplicate a reused key and reject a
      // conflicting payload; this bridge does not claim that guarantee.
      const idempotencyKey = action.idempotencyKey ?? crypto.randomUUID();

      try {
        return await withActivity("action", action.actionId, () =>
          request<HostActionReceipt<TResult>>(
            "action",
            "actions",
            {
              applicationKey: application.applicationKey,
              applicationVersion: application.applicationVersion,
              surfaceId: application.surface.surfaceId,
              surfaceVersion: application.surface.version,
              actionId: action.actionId,
              params: action.input as TInput,
              scope: scopeFrom(session.context),
            },
            idempotencyKey,
          ).then((receipt) => {
            assertHostActionReceipt(receipt);
            return receipt;
          }),
        );
      } catch (error) {
        notifySessionFailure("action", error);
        throw error;
      }
    },

    subscribe(listener: HostActivityListener): () => void {
      if (!active) return () => undefined;

      listeners.add(listener);
      let subscribed = true;

      return () => {
        if (!subscribed) return;
        subscribed = false;
        listeners.delete(listener);
      };
    },

    invalidate(): void {
      if (!active) return;
      active = false;
      const reason = staleContextError();
      for (const controller of inFlightControllers) controller.abort(reason);
      inFlightControllers.clear();
      listeners.clear();
    },
  };

  function notifySessionFailure(operation: HostActivityEvent["kind"], error: unknown): void {
    if (active && error instanceof HostBridgeError && isHostSessionFailure(error)) {
      options.onSessionFailure?.(operation, error);
    }
  }

  function assertBridgeActive(): void {
    if (!active) throw staleContextError();
  }
}

const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;

function snapshotQueryParams(value: HostQueryParams): HostQueryParams {
  assertHostQueryParams(value);
  return freezeQueryValue(value) as HostQueryParams;
}

function freezeQueryValue(value: HostJsonValue): HostJsonValue {
  if (Array.isArray(value)) {
    return Object.freeze(value.map((item) => freezeQueryValue(item)));
  }

  if (value !== null && typeof value === "object") {
    const copy: Record<string, HostJsonValue> = {};
    for (const [key, item] of Object.entries(value)) copy[key] = freezeQueryValue(item);
    return Object.freeze(copy);
  }

  return value;
}

function raceWithAbort<TResult>(
  promise: PromiseLike<TResult>,
  signal: AbortSignal,
  fallbackAbortReason: () => HostBridgeError,
): Promise<TResult> {
  return new Promise((resolve, reject) => {
    let settled = false;

    const cleanup = (): void => {
      signal.removeEventListener("abort", onAbort);
    };

    const resolveOnce = (value: TResult): void => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(value);
    };

    const rejectOnce = (reason: unknown): void => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(reason);
    };

    function onAbort(): void {
      rejectOnce(signal.reason instanceof HostBridgeError ? signal.reason : fallbackAbortReason());
    }

    void Promise.resolve(promise).then(resolveOnce, rejectOnce);
    if (signal.aborted) {
      onAbort();
      return;
    }

    signal.addEventListener("abort", onAbort, { once: true });
    if (signal.aborted) onAbort();
  });
}

function isRequestControlError(reason: unknown): reason is HostBridgeError {
  return (
    reason instanceof HostBridgeError &&
    (reason.code === "stale_context" || reason.code === "request_timed_out")
  );
}

function scopeFrom(context: HostContext) {
  switch (context.scope) {
    case "organization":
      return { scope: context.scope, organizationId: context.organizationId };
    case "user":
      return { scope: context.scope, userId: context.userId };
    case "admin":
      return { scope: context.scope };
    case "mission":
      return {
        organizationId: context.organizationId,
        missionId: context.missionId,
        spacecraftId: context.spacecraftId,
      };
    case "spacecraft":
      return {
        organizationId: context.organizationId,
        missionId: context.missionId,
        spacecraftId: context.spacecraftId,
      };
  }
}

function assertActiveContext(actual: HostContext, expected: HostContext): void {
  const sameContext =
    actual.scope === expected.scope &&
    (actual.scope === "organization"
      ? expected.scope === "organization" && actual.organizationId === expected.organizationId
      : actual.scope === "user"
        ? expected.scope === "user" && actual.userId === expected.userId
        : actual.scope === "admin"
          ? expected.scope === "admin"
          : (expected.scope === "mission" || expected.scope === "spacecraft") &&
            actual.missionId === expected.missionId &&
            actual.spacecraftId === expected.spacecraftId);

  if (!sameContext) {
    throw new HostBridgeError(
      400,
      "invalid_scope",
      "The requested application context is not active in this host.",
    );
  }
}

function assertSelectedQuery(query: HostQueryRequest, application: CatalogApplication): void {
  if (
    query.queryId !== application.surface.dataContract.id ||
    query.version !== application.surface.dataContract.version
  ) {
    throw new HostBridgeError(
      400,
      "unsupported_query",
      "The requested query contract is not declared for the selected application surface.",
    );
  }
}

function assertSelectedAction<TInput>(
  action: HostActionRequest<TInput>,
  application: CatalogApplication,
): void {
  if (
    action.applicationKey !== application.applicationKey ||
    action.applicationVersion !== application.applicationVersion ||
    (action.surfaceId !== undefined && action.surfaceId !== application.surface.surfaceId) ||
    (action.surfaceVersion !== undefined &&
      action.surfaceVersion !== application.surface.version) ||
    !application.surface.actions.includes(action.actionId)
  ) {
    throw new HostBridgeError(
      400,
      "unsupported_action",
      "The requested action is not declared for the selected application surface.",
    );
  }
}

function assertHostActionReceipt(value: unknown): asserts value is HostActionReceipt<unknown> {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    typeof (value as Record<string, unknown>).receiptId !== "string" ||
    (value as Record<string, unknown>).receiptId.trim() === "" ||
    typeof (value as Record<string, unknown>).completedAt !== "string" ||
    (value as Record<string, unknown>).completedAt.trim() === "" ||
    !("result" in value)
  ) {
    throw new HostBridgeError(
      200,
      "invalid_response",
      "The host action response was not a valid action receipt.",
    );
  }
}

function problemFor(status: number, payload: unknown): HostBridgeError {
  const code = validProblem(payload) ? payload.code : "host_request_failed";
  return new HostBridgeError(status, code, stableProblemMessage(status, code));
}

function invalidResponseFor(status: number, operation: HostActivityEvent["kind"]): HostBridgeError {
  return new HostBridgeError(
    status,
    "invalid_response",
    `The host ${operation} response was not valid JSON.`,
  );
}

export function isHostSessionFailure(reason: unknown): boolean {
  if (reason instanceof HostBridgeError) {
    return (
      reason.status === 401 ||
      reason.status === 403 ||
      ["unauthenticated", "invalid_session", "session_expired", "invalid_csrf"].includes(
        reason.code,
      )
    );
  }

  return (
    reason instanceof Error &&
    /HTTP (401|403)\b|unauthenticated|invalid session|csrf/i.test(reason.message)
  );
}

function validProblem(value: unknown): value is HostProblem {
  return (
    typeof value === "object" &&
    value !== null &&
    "schema" in value &&
    value.schema === "cadence.application-host-problem.v1" &&
    "code" in value &&
    typeof value.code === "string" &&
    "message" in value &&
    typeof value.message === "string"
  );
}

function activityEvent(
  kind: HostActivityEvent["kind"],
  contractId: string,
  status: HostActivityEvent["status"],
): HostActivityEvent {
  return {
    eventId: crypto.randomUUID(),
    kind,
    contractId,
    status,
    occurredAt: new Date().toISOString(),
  };
}

function stableProblemMessage(status: number, code: string): string {
  if (code === "invalid_csrf")
    return "The action was stopped because its security token was rejected.";
  if (["unauthenticated", "invalid_session", "session_expired"].includes(code)) {
    return "The host session is no longer authenticated.";
  }
  if (status === 401 || status === 403)
    return "The host rejected the request for the current session.";
  if (code === "stale_configuration") {
    return "The action was stopped because the application data changed.";
  }
  return "The host request failed.";
}

function staleContextError(): HostBridgeError {
  return new HostBridgeError(409, "stale_context", "The host context is no longer active.");
}

function requestTimedOutError(): HostBridgeError {
  return new HostBridgeError(0, "request_timed_out", "The host request exceeded its deadline.");
}

function referenceIdFor(): string {
  return crypto.randomUUID();
}
