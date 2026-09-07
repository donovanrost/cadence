import type { Component } from "vue";
import { inApplicationShell } from "./page-portal";
import { FederatedFullPageSurface } from "./federated_full_page_surface";

const modules = import.meta.glob<{ default: Component }>("./**/*.vue", { eager: true });
const pageNames = new Set([
  "FederatedFullPageSurface",
  "UserSession",
  "AdminModePage",
  "NoOrganizationPage",
  "OrganizationInvitationPage",
  "MissionApplicationManagement",
  "SpacecraftApplicationManagement",
  "ApplicationHost",
]);
const components = new Map<string, Component>([
  ["FederatedFullPageSurface", inApplicationShell(FederatedFullPageSurface)],
]);
for (const [path, module] of Object.entries(modules)) {
  const name = path
    .split("/")
    .at(-1)!
    .replace(/\.vue$/, "");
  if (components.has(name)) throw new Error(`Duplicate host component: ${name}`);
  components.set(name, pageNames.has(name) ? inApplicationShell(module.default) : module.default);
}
export function resolveHostComponent(name: string): Component {
  const component = components.get(name);
  if (!component) throw new Error(`Unknown host component: ${name}`);
  return component;
}
