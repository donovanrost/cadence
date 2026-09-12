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

const modules = import.meta.glob<{ default: Component }>("./**/*.vue", { eager: true });
const pageNames = new Set(["FederatedFullPageSurface", "ApplicationHost"]);
const components = new Map<string, Component>([
  ["UserSession", inApplicationShell(SignInPanel)],
  ["AdminModePage", inApplicationShell(AdminModePanel)],
  ["NoOrganizationPage", inApplicationShell(OrganizationAccessPanel)],
  ["OrganizationInvitationPage", inApplicationShell(InvitationAcceptancePanel)],
  ["FederatedFullPageSurface", inApplicationShell(FederatedFullPageSurface)],
  // Retain historical component names while their implementations live in the core feature.
  ["MissionApplicationManagement", inApplicationShell(MissionApplicationsPage)],
  ["SpacecraftApplicationManagement", inApplicationShell(SpacecraftApplicationsPage)],
]);
for (const [path, module] of Object.entries(modules)) {
  const filename = path.split("/").at(-1);
  if (!filename) throw new Error(`Invalid host component path: ${path}`);
  const name = filename.replace(/\.vue$/, "");
  if (components.has(name)) throw new Error(`Duplicate host component: ${name}`);
  components.set(name, pageNames.has(name) ? inApplicationShell(module.default) : module.default);
}
export function resolveHostComponent(name: string): Component {
  const component = components.get(name);
  if (!component) throw new Error(`Unknown host component: ${name}`);
  return component;
}
