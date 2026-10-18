/** Host-selected mission page placement. Reads and actions remain Phoenix-authorized. */
export const MISSION_PAGE_SLOT = "mission.page" as const;
export type MissionPageContext = {
  organizationId: string;
  missionId: string;
  resourceId?: string;
};
export type MissionPageSnapshot = {
  id: string;
  slot: typeof MISSION_PAGE_SLOT;
  version: number;
  context: MissionPageContext;
  status: "ready" | "unavailable";
  data?: unknown;
  token?: string;
};
export type MissionPagePort = {
  execute(action: string, input: Record<string, unknown>): Promise<unknown>;
  navigate(href: string): void;
};
export type MissionPageAction = {
  id: string;
  token: string;
  event: string;
  input: Record<string, unknown>;
};
export type MissionPageContribution<TComponent = unknown> = {
  readonly id: string;
  readonly slot: typeof MISSION_PAGE_SLOT;
  readonly version: 1;
  readonly title: string;
  readonly component: TComponent;
  readonly actions?: readonly string[];
  /** Only the feature interprets its DTO and binds any resource identity. */
  readonly read: (value: unknown, context: MissionPageContext) => Record<string, unknown>;
};
