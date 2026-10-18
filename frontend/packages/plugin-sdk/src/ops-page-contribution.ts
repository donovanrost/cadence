/** Host-selected Ops workspace page placement. Reads and actions remain Phoenix-authorized. */
export const OPS_PAGE_SLOT = "ops.page" as const;
export type OpsPageContext = {
  organizationId: string;
  missionId: string;
  resourceId?: string;
};
export type OpsPageSnapshot = {
  id: string;
  slot: typeof OPS_PAGE_SLOT;
  version: number;
  context: OpsPageContext;
  status: "ready" | "unavailable";
  data?: unknown;
  token?: string;
};
export type OpsPageNavigationPort = {
  navigate(this: void, href: string): void;
  /** Register a synchronous leave guard; dispose it with the feature instance. */
  guardNavigation?(this: void, guard: () => boolean): () => void;
};
export type OpsPageNavigationResult = "completed" | "cancelled" | "unchanged" | "failed";
export type SettledOpsPageNavigationPort = {
  navigate(this: void, href: string): Promise<OpsPageNavigationResult>;
};
export type OpsPagePort = OpsPageNavigationPort & {
  execute(action: string, input: Record<string, unknown>): Promise<unknown>;
};
export type GuardedOpsPagePort = OpsPagePort &
  Required<Pick<OpsPageNavigationPort, "guardNavigation">>;
/** Captured page reads return domain data without replacing the mounted page. */
export type OpsPageReadPort = { read(): Promise<unknown> };
/** Changes are wake-ups; the feature reads again through its captured, authorized port. */
export type LiveOpsPageReadPort = OpsPageReadPort & {
  subscribe(listener: () => void): () => void;
};
export type OpsPageUpdateSubscription = (
  request: OpsPageReadRequest,
  listener: () => void,
) => () => void;
export type OpsPageReadRequest = { id: string; token: string };
export type OpsPageAction = {
  id: string;
  token: string;
  event: string;
  input: Record<string, unknown>;
};
export type OpsPageContribution<TComponent = unknown> = {
  readonly id: string;
  readonly slot: typeof OPS_PAGE_SLOT;
  readonly version: 1;
  readonly title: string;
  readonly component: TComponent;
  readonly actions?: readonly string[];
  /** Read-only pages may navigate without receiving an action port or action token. */
  readonly navigation?: true | "settled";
  /** Supplies a read-only port with page-instance and context admission. */
  readonly query?: true | "live";
  /** A submitted workflow must be able to protect its mounted lifetime. */
  readonly guardNavigation?: true;
  /** Only the feature interprets its DTO and binds any resource identity. */
  readonly read: (value: unknown, context: OpsPageContext) => Record<string, unknown>;
};
