export type ApplicationScope = "organization" | "mission" | "spacecraft";

export interface HostActor {
  displayName: string;
  permissions: readonly string[];
}

interface BaseHostContext {
  organizationId: string;
  missionId: string;
  missionName: string;
  actor: HostActor;
}

export interface MissionHostContext extends BaseHostContext {
  scope: "mission";
  spacecraftId: null;
  spacecraftName: null;
}

export interface SpacecraftHostContext extends BaseHostContext {
  scope: "spacecraft";
  spacecraftId: string;
  spacecraftName: string;
}

export type HostContext = MissionHostContext | SpacecraftHostContext;

export function assertHostContext(value: unknown): asserts value is HostContext {
  if (!isHostContext(value)) throw new Error("Host context is invalid.");
}

export function isHostContext(value: unknown): value is HostContext {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.organizationId) ||
    !nonEmptyString(value.missionId) ||
    !nonEmptyString(value.missionName) ||
    !isRecord(value.actor) ||
    !nonEmptyString(value.actor.displayName) ||
    !Array.isArray(value.actor.permissions) ||
    !value.actor.permissions.every(nonEmptyString)
  ) {
    return false;
  }

  if (value.scope === "mission") {
    return value.spacecraftId === null && value.spacecraftName === null;
  }

  return (
    value.scope === "spacecraft" &&
    nonEmptyString(value.spacecraftId) &&
    nonEmptyString(value.spacecraftName)
  );
}

export interface HostQueryRequest {
  queryId: string;
  version: number;
  context: HostContext;
}

export interface HostActionRequest<TInput = unknown> {
  applicationKey: string;
  applicationVersion: number;
  actionId: string;
  input: TInput;
  context: HostContext;
}

export interface HostActionReceipt<TResult = unknown> {
  receiptId: string;
  completedAt: string;
  result: TResult;
}

export interface HostActivityEvent {
  eventId: string;
  kind: "query" | "action";
  contractId: string;
  status: "started" | "completed" | "failed";
  occurredAt: string;
}

export type HostActivityListener = (event: HostActivityEvent) => void;

export interface HostBridge {
  query<TResult>(request: HostQueryRequest): Promise<TResult>;
  execute<TInput, TResult>(request: HostActionRequest<TInput>): Promise<HostActionReceipt<TResult>>;
  subscribe(listener: HostActivityListener): () => void;
}

export interface FederatedApplicationProps {
  context: HostContext;
  bridge: HostBridge;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
