import NotificationsBell from "./NotificationsBell.vue";
import NotificationsPage from "./NotificationsPage.vue";

import type { Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";

export const exposedComponents = {
  NotificationsPage,
  NotificationsBell,
};

/** The host surface id is the only renderer selection authority in this remote. */
export const surfaceComponents = {
  notifications: NotificationsPage,
  notifications_bell: NotificationsBell,
} satisfies Record<OrganizationAdminSurface, Component>;
