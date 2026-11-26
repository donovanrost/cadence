import BrowserHost from "./BrowserHost.vue";
import ApplicationShell from "./ApplicationShell.vue";
import HostPage from "./HostPage.vue";
import { lazyHostPage } from "./lazy-host-page";
import type { Component } from "vue";
import { inApplicationShell } from "./page-portal";
import { FederatedFullPageSurface } from "./federated_full_page_surface";

const components = new Map<string, Component>([
  ["BrowserHost", BrowserHost],
  ["ApplicationShell", ApplicationShell],
  ["HostPage", HostPage],
  ["StatusBadge", lazyHostPage("StatusBadge", () => import("./StatusBadge.vue"))],
  ["UtcClock", lazyHostPage("UtcClock", () => import("./UtcClock.vue"))],
  ["AuthLayoutBrand", lazyHostPage("AuthLayoutBrand", () => import("./AuthLayoutBrand.vue"))],
  ["FederatedFullPageSurface", inApplicationShell(FederatedFullPageSurface)],
]);
export function resolveHostComponent(name: string): Component {
  const component = components.get(name);
  if (!component) throw new Error(`Unknown host component: ${name}`);
  return component;
}
