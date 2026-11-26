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
