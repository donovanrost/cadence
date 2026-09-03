import type {
  CatalogApplication,
  HostActionReceipt,
  HostActionRequest,
  HostActivityEvent,
  HostActivityListener,
  HostBridge,
  HostContext,
  HostQueryRequest,
  HostSessionDescriptor,
} from "@cadence/plugin-sdk";

interface HostProblem {
  schema: "cadence.application-host-problem.v1";
  code: string;
  message: string;
}

interface BridgeOptions {
  fetch?: typeof globalThis.fetch;
  onSessionFailure?: (
    operation: HostActivityEvent["kind"],
    error: HostBridgeError,
  ) => void;
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
  const listeners = new Set<HostActivityListener>();
  let active = true;

  function publish(event: HostActivityEvent): void {
    for (const listener of listeners) listener(event);
  }

  async function withActivity<TResult>(
    kind: HostActivityEvent["kind"],
    contractId: string,
    operation: () => Promise<TResult>,
  ): Promise<TResult> {
    publish(activityEvent(kind, contractId, "started"));

    try {
      const result = await operation();
      publish(activityEvent(kind, contractId, "completed"));
      return result;
    } catch (error) {
      publish(activityEvent(kind, contractId, "failed"));
      throw error;
    }
  }

  async function request<TResult>(path: string, body: unknown, idempotencyKey?: string) {
    assertBridgeActive();

    let response: Response;
    try {
      response = await fetcher(`${session.bridgeBaseUrl}/${path}`, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-cadence-poc-session": session.sessionId,
          "x-csrf-token": session.csrfToken,
          ...(idempotencyKey ? { "idempotency-key": idempotencyKey } : {}),
        },
        body: JSON.stringify(body),
      });
    } catch {
      if (!active) throw staleContextError();
      throw new HostBridgeError(0, "transport_failed", "The host request could not be completed.");
    }

    if (!active) throw staleContextError();
    const payload: unknown = await response.json().catch(() => undefined);
    if (!response.ok) throw problemFor(response.status, payload);
    return payload as TResult;
  }

  return {
    async query<TResult>(query: HostQueryRequest): Promise<TResult> {
      assertBridgeActive();
      assertActiveContext(query.context, session.context);
      assertSelectedQuery(query, application);

      try {
        return await withActivity("query", query.queryId, () =>
          request<TResult>("query", {
            applicationKey: application.applicationKey,
            applicationVersion: application.applicationVersion,
            surfaceId: application.surface.surfaceId,
            surfaceVersion: application.surface.version,
            queryId: query.queryId,
            queryVersion: query.version,
            scope: scopeFrom(session.context),
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
      const idempotencyKey = action.idempotencyKey || crypto.randomUUID();

      try {
        return await withActivity("action", action.actionId, () =>
          request<HostActionReceipt<TResult>>(
            "actions",
            {
              applicationKey: application.applicationKey,
              applicationVersion: application.applicationVersion,
              surfaceId: application.surface.surfaceId,
              surfaceVersion: application.surface.version,
              actionId: action.actionId,
              input: action.input as TInput,
              scope: scopeFrom(session.context),
            },
            idempotencyKey,
          ),
        );
      } catch (error) {
        notifySessionFailure("action", error);
        throw error;
      }
    },

    subscribe(listener: HostActivityListener): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },

    invalidate(): void {
      active = false;
      listeners.clear();
    },
  };

  function notifySessionFailure(
    operation: HostActivityEvent["kind"],
    error: unknown,
  ): void {
    if (active && error instanceof HostBridgeError && isHostSessionFailure(error)) {
      options.onSessionFailure?.(operation, error);
    }
  }

  function assertBridgeActive(): void {
    if (!active) throw staleContextError();
  }
}

function scopeFrom(context: HostContext) {
  return {
    organizationId: context.organizationId,
    missionId: context.missionId,
    spacecraftId: context.spacecraftId,
  };
}

function assertActiveContext(actual: HostContext, expected: HostContext): void {
  if (
    actual.scope !== expected.scope ||
    actual.organizationId !== expected.organizationId ||
    actual.missionId !== expected.missionId ||
    actual.spacecraftId !== expected.spacecraftId
  ) {
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
    !application.surface.actions.includes(action.actionId)
  ) {
    throw new HostBridgeError(
      400,
      "unsupported_action",
      "The requested action is not declared for the selected application surface.",
    );
  }
}

function problemFor(status: number, payload: unknown): HostBridgeError {
  const code = validProblem(payload) ? payload.code : "host_request_failed";
  return new HostBridgeError(status, code, stableProblemMessage(status, code));
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

  return reason instanceof Error && /HTTP (401|403)\b|unauthenticated|invalid session|csrf/i.test(reason.message);
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
  if (code === "invalid_csrf") return "The action was stopped because its security token was rejected.";
  if (["unauthenticated", "invalid_session", "session_expired"].includes(code)) {
    return "The host session is no longer authenticated.";
  }
  if (status === 401 || status === 403) return "The host rejected the request for the current session.";
  if (code === "stale_configuration") {
    return "The action was stopped because the application data changed.";
  }
  return "The host request failed.";
}

function staleContextError(): HostBridgeError {
  return new HostBridgeError(409, "stale_context", "The host context is no longer active.");
}

function referenceIdFor(): string {
  return crypto.randomUUID();
}
