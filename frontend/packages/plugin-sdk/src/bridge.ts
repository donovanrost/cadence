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

export type HostJsonValue =
  | string
  | number
  | boolean
  | null
  | HostJsonValue[]
  | { readonly [key: string]: HostJsonValue };

export type HostQueryParams = Readonly<Record<string, HostJsonValue>>;

export const HOST_QUERY_PARAMS_MAX_BYTES = 16_384;
export const HOST_QUERY_PARAMS_MAX_DEPTH = 4;
export const HOST_QUERY_PARAMS_MAX_KEYS = 64;
export const HOST_QUERY_PARAMS_MAX_ARRAY_ITEMS = 32;
export const HOST_QUERY_PARAMS_MAX_STRING_BYTES = 256;

const forbiddenQueryParamKeys = new Set(["__proto__", "constructor", "prototype"]);

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
  /** Route parameters are captured by the Phoenix host and cannot be supplied by callers. */
  readonly params?: never;
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

export function assertHostQueryParams(value: unknown): asserts value is HostQueryParams {
  const state = {keys: 0};

  if (!isPlainObject(value)) throw new Error("Host query parameters must be a plain JSON object.");
  visitQueryValue(value, 0, state, true);

  const serialized = JSON.stringify(value);
  if (serialized === undefined || utf8ByteLength(serialized) > HOST_QUERY_PARAMS_MAX_BYTES) {
    throw new Error("Host query parameters exceed the maximum JSON size.");
  }
}

export function isHostQueryParams(value: unknown): value is HostQueryParams {
  try {
    assertHostQueryParams(value);
    return true;
  } catch {
    return false;
  }
}

function visitQueryValue(
  value: unknown,
  depth: number,
  state: {keys: number},
  root = false,
): void {
  if (typeof value === "string") {
    if (utf8ByteLength(value) > HOST_QUERY_PARAMS_MAX_STRING_BYTES) {
      throw new Error("Host query parameter strings are too large.");
    }
    return;
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("Host query parameters contain an invalid number.");
    return;
  }

  if (value === null || typeof value === "boolean") return;

  if (Array.isArray(value)) {
    if (root) throw new Error("Host query parameters must be a plain JSON object.");
    if (depth > HOST_QUERY_PARAMS_MAX_DEPTH || value.length > HOST_QUERY_PARAMS_MAX_ARRAY_ITEMS) {
      throw new Error("Host query parameters exceed the maximum depth or array size.");
    }
    value.forEach((item) => visitQueryValue(item, depth + 1, state));
    return;
  }

  if (!isPlainObject(value) || depth > HOST_QUERY_PARAMS_MAX_DEPTH) {
    throw new Error("Host query parameters contain an invalid JSON value.");
  }

  for (const key of Object.keys(value)) {
    state.keys += 1;
    if (state.keys > HOST_QUERY_PARAMS_MAX_KEYS) {
      throw new Error("Host query parameters contain too many keys.");
    }
    if (forbiddenQueryParamKeys.has(key) || utf8ByteLength(key) > HOST_QUERY_PARAMS_MAX_STRING_BYTES) {
      throw new Error("Host query parameters contain a forbidden or oversized key.");
    }

    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !descriptor.enumerable || !("value" in descriptor)) {
      throw new Error("Host query parameters must contain data properties only.");
    }
    visitQueryValue(descriptor.value, depth + 1, state);
  }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function utf8ByteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
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
