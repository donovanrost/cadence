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
  {
    surfaceId: "admin_home",
    scope: "admin",
    component: "AdminHome",
    purpose: "overview",
    placement: "application_workspace" as const,
    navigation: { label: "Overview", order: 70 },
    query: { id: "cadence.platform_admin.home", version: 1 },
    actions: [] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "admin_runtime",
    scope: "admin",
    component: "AdminRuntime",
    purpose: "activity",
    placement: "application_workspace" as const,
    navigation: { label: "Runtime", order: 80 },
    query: { id: "cadence.platform_admin.runtime", version: 1 },
    actions: ["refresh_runtime", "filter_runtime_decisions"] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "admin_organizations",
    scope: "admin",
    component: "AdminOrganizationListPage",
    purpose: "collection",
    placement: "application_workspace" as const,
    navigation: { label: "Organizations", order: 90 },
    query: { id: "cadence.platform_admin.organizations", version: 1 },
    actions: [] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "admin_organization_new",
    scope: "admin",
    component: "AdminOrganizationNew",
    purpose: "configuration",
    placement: "application_workspace" as const,
    navigation: { label: "New Organization", order: 100 },
    query: { id: "cadence.platform_admin.organization.new", version: 1 },
    actions: ["validate_organization", "create_organization"] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "admin_organization_show",
    scope: "admin",
    component: "AdminOrganizationShow",
    purpose: "subject_detail",
    placement: "application_workspace" as const,
    navigation: { label: "Organization", order: 110 },
    query: { id: "cadence.platform_admin.organization.show", version: 1 },
    actions: ["issue_service_identity", "dismiss_service_token", "open_organization"] as const,
    exposedModule: "./Application",
  },
  {
    surfaceId: "admin_organization_invite",
    scope: "admin",
    component: "AdminOrganizationInvite",
    purpose: "configuration",
    placement: "application_workspace" as const,
    navigation: { label: "Invite User", order: 120 },
    query: { id: "cadence.platform_admin.organization.invite", version: 1 },
    actions: ["validate_invitation", "invite_organization_member"] as const,
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
