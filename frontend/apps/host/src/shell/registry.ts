import BrowserHost from "./BrowserHost.vue";
import ApplicationShell from "./ApplicationShell.vue";
import HostPage from "./HostPage.vue";
import { lazyHostPage } from "./lazy-host-page";
import type { Component } from "vue";
import { inApplicationShell } from "./page-portal";
import { FederatedFullPageSurface } from "./federated_full_page_surface";
import { MissionApplicationsPage, SpacecraftApplicationsPage } from "../capability-management";

import {
  SignInPanel,
  AdminModePanel,
  OrganizationAccessPanel,
  InvitationAcceptancePanel,
} from "../auth-and-navigation";

const components = new Map<string, Component>([
  ["BrowserHost", BrowserHost],
  ["ApplicationShell", ApplicationShell],
  ["HostPage", HostPage],
  [
    "ApplicationHost",
    inApplicationShell(lazyHostPage("ApplicationHost", () => import("./ApplicationHost.vue"))),
  ],
  ["StatusBadge", lazyHostPage("StatusBadge", () => import("./StatusBadge.vue"))],
  ["UtcClock", lazyHostPage("UtcClock", () => import("./UtcClock.vue"))],
  ["AuthLayoutBrand", lazyHostPage("AuthLayoutBrand", () => import("./AuthLayoutBrand.vue"))],
  [
    "ApplicationStats",
    lazyHostPage("ApplicationStats", () => import("./application_host/ApplicationStats.vue")),
  ],
  [
    "ApplicationNavigation",
    lazyHostPage(
      "ApplicationNavigation",
      () => import("./application_host/ApplicationNavigation.vue"),
    ),
  ],
  [
    "ApplicationDiagnostics",
    lazyHostPage(
      "ApplicationDiagnostics",
      () => import("./application_host/ApplicationDiagnostics.vue"),
    ),
  ],
  ["UserSession", inApplicationShell(SignInPanel)],
  ["AdminModePage", inApplicationShell(AdminModePanel)],
  ["NoOrganizationPage", inApplicationShell(OrganizationAccessPanel)],
  ["OrganizationInvitationPage", inApplicationShell(InvitationAcceptancePanel)],
  ["FederatedFullPageSurface", inApplicationShell(FederatedFullPageSurface)],
  // Retain historical component names while their implementations live in the core feature.
  ["MissionApplicationManagement", inApplicationShell(MissionApplicationsPage)],
  ["SpacecraftApplicationManagement", inApplicationShell(SpacecraftApplicationsPage)],
]);
export function resolveHostComponent(name: string): Component {
  const component = components.get(name);
  if (!component) throw new Error(`Unknown host component: ${name}`);
  return component;
}
