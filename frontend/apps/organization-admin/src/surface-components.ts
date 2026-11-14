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
};

/** The host surface id is the only renderer selection authority in this remote. */
export const surfaceComponents = {
  organization_home: OrganizationHome,
  provider_accounts: ProviderAccountListPage,
  provider_account_new: ProviderAccountNew,
  provider_account_show: ProviderAccountShow,
  notifications: NotificationsPage,
  notifications_bell: NotificationsBell,
} satisfies Record<OrganizationAdminSurface, Component>;
