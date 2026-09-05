import { createApp, type App } from "vue";
import AppRoot from "./App.vue";

export type HostAppProps = Record<string, unknown>;

/** Canonical standalone host bootstrap. Phoenix uses phoenix-bootstrap.ts. */
export function bootstrapHost(root: HTMLElement, props: HostAppProps = {}): App {
  if (root.nodeType !== 1) throw new Error("The Cadence host requires an element root.");
  const app = createApp(AppRoot, props);
  app.mount(root);
  return app;
}
