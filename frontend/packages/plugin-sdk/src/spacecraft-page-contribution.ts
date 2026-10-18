/** Host-selected spacecraft page placement; no installation or action authority. */
export const SPACECRAFT_PAGE_SLOT = "spacecraft.page" as const;
export type SpacecraftPageContext = {
  organizationId: string;
  missionId: string;
  spacecraftId: string;
};
export type SpacecraftPageSnapshot = {
  id: string;
  slot: typeof SPACECRAFT_PAGE_SLOT;
  version: number;
  context: SpacecraftPageContext;
  status: "ready" | "unavailable";
  data?: unknown;
};
export type SpacecraftPageContribution<TComponent = unknown> = {
  readonly id: string;
  readonly slot: typeof SPACECRAFT_PAGE_SLOT;
  readonly version: 1;
  readonly title: string;
  readonly component: TComponent;
  /** Return only admitted component props. The host does not interpret domain DTOs. */
  readonly read: (value: unknown, context: SpacecraftPageContext) => Record<string, unknown>;
};
