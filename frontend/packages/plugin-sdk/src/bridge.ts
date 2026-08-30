export type ApplicationScope = "organization" | "mission" | "spacecraft";

export interface HostContext {
  organizationId: string;
  missionId: string;
  missionName: string;
  spacecraftId: string;
  spacecraftName: string;
  actor: {
    displayName: string;
    permissions: readonly string[];
  };
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
