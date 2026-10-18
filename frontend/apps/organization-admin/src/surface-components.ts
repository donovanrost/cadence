import AdminHome from "./AdminHome.vue";
import AdminOrganizationInvite from "./AdminOrganizationInvite.vue";
import AdminOrganizationListPage from "./AdminOrganizationListPage.vue";
import AdminOrganizationNew from "./AdminOrganizationNew.vue";
import AdminOrganizationShow from "./AdminOrganizationShow.vue";
import AdminRuntime from "./AdminRuntime.vue";
import NotificationsBell from "./NotificationsBell.vue";
import NotificationsPage from "./NotificationsPage.vue";
import OrganizationHome from "./OrganizationHome.vue";
import ProviderAccountListPage from "./ProviderAccountListPage.vue";
import ProviderAccountNew from "./ProviderAccountNew.vue";
import ProviderAccountShow from "./ProviderAccountShow.vue";

import type { Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";

export const exposedComponents = {
  OrganizationHome,
  ProviderAccountListPage,
  ProviderAccountNew,
  ProviderAccountShow,
  NotificationsPage,
  NotificationsBell,
  AdminHome,
  AdminRuntime,
  AdminOrganizationListPage,
  AdminOrganizationNew,
  AdminOrganizationShow,
  AdminOrganizationInvite,
};

/** The host surface id is the only renderer selection authority in this remote. */
export const surfaceComponents = {
  organization_home: OrganizationHome,
  provider_accounts: ProviderAccountListPage,
  provider_account_new: ProviderAccountNew,
  provider_account_show: ProviderAccountShow,
  notifications: NotificationsPage,
  notifications_bell: NotificationsBell,
  admin_home: AdminHome,
  admin_runtime: AdminRuntime,
  admin_organizations: AdminOrganizationListPage,
  admin_organization_new: AdminOrganizationNew,
  admin_organization_show: AdminOrganizationShow,
  admin_organization_invite: AdminOrganizationInvite,
} satisfies Record<OrganizationAdminSurface, Component>;
