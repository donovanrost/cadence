import type {
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
}

export class HostBridgeError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "HostBridgeError";
    this.status = status;
    this.code = code;
  }
}

export function createHttpHostBridge(
  session: HostSessionDescriptor,
  options: BridgeOptions = {},
): HostBridge {
  const fetcher = options.fetch ?? globalThis.fetch;
  const listeners = new Set<HostActivityListener>();

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
    const response = await fetcher(`${session.bridgeBaseUrl}/${path}`, {
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

    const payload: unknown = await response.json().catch(() => undefined);
    if (!response.ok) throw problemFor(response.status, payload);
    return payload as TResult;
  }

  return {
    async query<TResult>(query: HostQueryRequest): Promise<TResult> {
      assertActiveContext(query.context, session.context);

      return withActivity("query", query.queryId, () =>
        request<TResult>("query", {
          queryId: query.queryId,
          version: query.version,
          scope: scopeFrom(session.context),
        }),
      );
    },

    async execute<TInput, TResult>(
      action: HostActionRequest<TInput>,
    ): Promise<HostActionReceipt<TResult>> {
      assertActiveContext(action.context, session.context);
      const idempotencyKey = crypto.randomUUID();

      return withActivity("action", action.actionId, () =>
        request<HostActionReceipt<TResult>>(
          "actions",
          {
            applicationKey: action.applicationKey,
            applicationVersion: action.applicationVersion,
            actionId: action.actionId,
            input: action.input as TInput,
            scope: scopeFrom(session.context),
          },
          idempotencyKey,
        ),
      );
    },

    subscribe(listener: HostActivityListener): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
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

function problemFor(status: number, payload: unknown): HostBridgeError {
  if (validProblem(payload)) return new HostBridgeError(status, payload.code, payload.message);
  return new HostBridgeError(status, "host_request_failed", "The host request failed.");
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
