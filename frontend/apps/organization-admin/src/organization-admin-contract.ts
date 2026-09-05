import type { SurfacePurpose } from "@cadence/plugin-sdk";

export const SURFACE_CONTRACTS = [
  {
    surfaceId: "organization_home",
    component: "OrganizationHome",
    purpose: "overview" as SurfacePurpose,
    query: { id: "cadence.organization.home", version: 1 },
    actions: [] as const
  },
  {
    surfaceId: "provider_accounts",
    component: "ProviderAccountListPage",
    purpose: "overview" as SurfacePurpose,
    query: { id: "cadence.organization.provider_accounts.list", version: 1 },
    actions: [] as const
  },
  {
    surfaceId: "provider_account_new",
    component: "ProviderAccountNew",
    purpose: "configuration" as SurfacePurpose,
    query: { id: "cadence.organization.provider_accounts.new", version: 1 },
    actions: ["validate_provider_account", "register_provider_account"] as const
  },
  {
    surfaceId: "provider_account_show",
    component: "ProviderAccountShow",
    purpose: "configuration" as SurfacePurpose,
    query: { id: "cadence.organization.provider_account.show", version: 1 },
    actions: [
      "validate_provider_account",
      "rotate_provider_credential",
      "revoke_provider_credential",
      "grant_provider_account_mission",
      "revoke_provider_account_mission"
    ] as const
  },
  {
    surfaceId: "notifications",
    component: "NotificationsPage",
    purpose: "activity" as SurfacePurpose,
    query: { id: "cadence.organization.notifications", version: 1 },
    actions: ["accept_invitation", "mark_notification_read"] as const
  },
  {
    surfaceId: "notifications_bell",
    component: "NotificationsBell",
    purpose: "activity" as SurfacePurpose,
    query: { id: "cadence.organization.notifications_bell", version: 1 },
    actions: ["mark_notification_read"] as const
  },
  {
    surfaceId: "admin_home",
    component: "AdminHome",
    purpose: "overview" as SurfacePurpose,
    query: { id: "cadence.platform_admin.home", version: 1 },
    actions: [] as const
  },
  {
    surfaceId: "admin_runtime",
    component: "AdminRuntime",
    purpose: "activity" as SurfacePurpose,
    query: { id: "cadence.platform_admin.runtime", version: 1 },
    actions: ["refresh_runtime", "filter_runtime_decisions"] as const
  },
  {
    surfaceId: "admin_organizations",
    component: "AdminOrganizationListPage",
    purpose: "overview" as SurfacePurpose,
    query: { id: "cadence.platform_admin.organizations", version: 1 },
    actions: [] as const
  },
  {
    surfaceId: "admin_organization_new",
    component: "AdminOrganizationNew",
    purpose: "configuration" as SurfacePurpose,
    query: { id: "cadence.platform_admin.organization.new", version: 1 },
    actions: ["validate_organization", "create_organization"] as const
  },
  {
    surfaceId: "admin_organization_show",
    component: "AdminOrganizationShow",
    purpose: "overview" as SurfacePurpose,
    query: { id: "cadence.platform_admin.organization.show", version: 1 },
    actions: ["issue_service_identity", "dismiss_service_token", "open_organization"] as const
  },
  {
    surfaceId: "admin_organization_invite",
    component: "AdminOrganizationInvite",
    purpose: "configuration" as SurfacePurpose,
    query: { id: "cadence.platform_admin.organization.invite", version: 1 },
    actions: ["validate_invitation", "invite_organization_member"] as const
  }
] as const;

export type OrganizationAdminSurface = (typeof SURFACE_CONTRACTS)[number]["surfaceId"];

export const HOST_OWNED_FLOWS = {
  sign_in: "Phoenix authentication and session establishment",
  invitation_acceptance: "Phoenix validates and persists membership acceptance",
  no_organization_bootstrap: "Phoenix establishes the first organization scope",
  admin_mode_transition: "Phoenix owns admin-mode reauthentication and session transition"
} as const;
