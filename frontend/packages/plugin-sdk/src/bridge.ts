export type ApplicationScope = "organization" | "user" | "admin" | "mission" | "spacecraft";

export interface HostActor {
  displayName: string;
  permissions: readonly string[];
}

interface BaseHostContext {
  actor: HostActor;
}

export interface OrganizationHostContext extends BaseHostContext {
  scope: "organization";
  organizationId: string;
  missionId: null;
  missionName: null;
  spacecraftId: null;
  spacecraftName: null;
}

/** User/account context is intentionally independent of an organization. */
export interface UserHostContext extends BaseHostContext {
  scope: "user";
  organizationId: null;
  userId: string;
  missionId: null;
  missionName: null;
  spacecraftId: null;
  spacecraftName: null;
}

/** Admin/global context is resource-free; authorization remains Phoenix-owned. */
export interface AdminHostContext extends BaseHostContext {
  scope: "admin";
  organizationId: null;
  missionId: null;
  missionName: null;
  spacecraftId: null;
  spacecraftName: null;
}

export interface MissionHostContext extends BaseHostContext {
  scope: "mission";
  organizationId: string;
  spacecraftId: null;
  spacecraftName: null;
  missionId: string;
  missionName: string;
}

export interface SpacecraftHostContext extends BaseHostContext {
  scope: "spacecraft";
  organizationId: string;
  missionId: string;
  missionName: string;
  spacecraftId: string;
  spacecraftName: string;
}

export type HostContext =
  | OrganizationHostContext
  | UserHostContext
  | AdminHostContext
  | MissionHostContext
  | SpacecraftHostContext;

export function assertHostContext(value: unknown): asserts value is HostContext {
  if (!isHostContext(value)) throw new Error("Host context is invalid.");
}

export function isHostContext(value: unknown): value is HostContext {
  if (!isRecord(value) || !validActor(value.actor)) {
    return false;
  }

  switch (value.scope) {
    case "organization":
      return (
        nonEmptyString(value.organizationId) &&
        value.missionId === null &&
        value.missionName === null &&
        value.spacecraftId === null &&
        value.spacecraftName === null
      );
    case "user":
      return (
        value.organizationId === null &&
        nonEmptyString(value.userId) &&
        value.missionId === null &&
        value.missionName === null &&
        value.spacecraftId === null &&
        value.spacecraftName === null
      );
    case "admin":
      return (
        value.organizationId === null &&
        value.missionId === null &&
        value.missionName === null &&
        value.spacecraftId === null &&
        value.spacecraftName === null
      );
    case "mission":
      return (
        nonEmptyString(value.organizationId) &&
        nonEmptyString(value.missionId) &&
        nonEmptyString(value.missionName) &&
        value.spacecraftId === null &&
        value.spacecraftName === null
      );
    case "spacecraft":
      return (
        nonEmptyString(value.organizationId) &&
        nonEmptyString(value.missionId) &&
        nonEmptyString(value.missionName) &&
        nonEmptyString(value.spacecraftId) &&
        nonEmptyString(value.spacecraftName)
      );
    default:
      return false;
  }
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

function validActor(value: unknown): value is HostActor {
  return (
    isRecord(value) &&
    nonEmptyString(value.displayName) &&
    Array.isArray(value.permissions) &&
    value.permissions.every(nonEmptyString)
  );
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
