/** Compiled organization-page placement, independent of frontend release admission. */
export const ORGANIZATION_PAGE_SLOT = "organization.page" as const;
export type OrganizationPageContext = { organizationId: string; resourceId?: string };
export type OrganizationPagePort = {
  execute(action: string, input: Record<string, unknown>): Promise<unknown>;
  navigate(href: string): void;
};
export type OrganizationPageAction = {
  id: string;
  token: string;
  event: string;
  input: Record<string, unknown>;
};
export type OrganizationPageContribution<TComponent = unknown> = {
  readonly id: string;
  readonly slot: typeof ORGANIZATION_PAGE_SLOT;
  readonly version: 1;
  readonly title: string;
  readonly component: TComponent;
  readonly actions?: readonly string[];
  readonly read: (value: unknown, context: OrganizationPageContext) => Record<string, unknown>;
};
