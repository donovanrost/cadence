import type { SurfacePurpose } from "@cadence/plugin-sdk";

export type OrganizationAdminScope = "organization" | "user" | "admin";

type OrganizationAdminSurfaceContract = {
  readonly surfaceId: string;
  readonly scope: OrganizationAdminScope;
  readonly component: string;
  readonly purpose: SurfacePurpose;
  readonly placement: "application_workspace";
  readonly navigation: { readonly label: string; readonly order: number };
  readonly query: { readonly id: string; readonly version: 1 };
  readonly actions: readonly string[];
  readonly exposedModule: "./Application";
};

export const SURFACE_CONTRACTS = [
  {
    surfaceId: "organization_home",
    scope: "organization",
    component: "OrganizationHome",
    purpose: "overview",
    placement: "application_workspace" as const,
    navigation: { label: "Overview", order: 10 },
    query: { id: "cadence.organization.home", version: 1 },
    actions: [] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "provider_accounts",
    scope: "organization",
    component: "ProviderAccountListPage",
    purpose: "collection",
    placement: "application_workspace" as const,
    navigation: { label: "Provider Accounts", order: 20 },
    query: { id: "cadence.organization.provider_accounts.list", version: 1 },
    actions: [] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "provider_account_new",
    scope: "organization",
    component: "ProviderAccountNew",
    purpose: "configuration",
    placement: "application_workspace" as const,
    navigation: { label: "New Provider Account", order: 30 },
    query: { id: "cadence.organization.provider_accounts.new", version: 1 },
    actions: ["validate_provider_account_form", "register_provider_account"] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "provider_account_show",
    scope: "organization",
    component: "ProviderAccountShow",
    purpose: "subject_detail",
    placement: "application_workspace" as const,
    navigation: { label: "Provider Account", order: 40 },
    query: { id: "cadence.organization.provider_account.show", version: 1 },
    actions: [
      "validate_provider_account",
      "rotate_provider_credential",
      "revoke_provider_credential",
      "grant_provider_account_mission",
      "revoke_provider_account_mission",
    ] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "notifications",
    scope: "user",
    component: "NotificationsPage",
    purpose: "activity",
    placement: "application_workspace" as const,
    navigation: { label: "Notifications", order: 50 },
    query: { id: "cadence.organization.notifications", version: 1 },
    actions: ["accept_invitation", "mark_notification_read"] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "notifications_bell",
    scope: "user",
    component: "NotificationsBell",
    purpose: "activity",
    placement: "application_workspace" as const,
    navigation: { label: "Notifications Bell", order: 60 },
    query: { id: "cadence.organization.notifications_bell", version: 1 },
    actions: ["mark_notification_read"] as const,
    exposedModule: "./Application",
  },
] as const satisfies readonly OrganizationAdminSurfaceContract[];

export type OrganizationAdminSurface = (typeof SURFACE_CONTRACTS)[number]["surfaceId"];

export const HOST_OWNED_FLOWS = {
  sign_in: "Phoenix authentication and session establishment",
  invitation_acceptance: "Phoenix validates and persists membership acceptance",
  no_organization_bootstrap: "Phoenix establishes the first organization scope",
  admin_mode_transition: "Phoenix owns admin-mode reauthentication and session transition",
} as const;
