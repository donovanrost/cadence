import NotificationsBell from "./NotificationsBell.vue";
import NotificationsPage from "./NotificationsPage.vue";
import OrganizationHome from "./OrganizationHome.vue";

import type { Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";

export const exposedComponents = {
  OrganizationHome,
  NotificationsPage,
  NotificationsBell,
};

/** The host surface id is the only renderer selection authority in this remote. */
export const surfaceComponents = {
  organization_home: OrganizationHome,
  notifications: NotificationsPage,
  notifications_bell: NotificationsBell,
} satisfies Record<OrganizationAdminSurface, Component>;
