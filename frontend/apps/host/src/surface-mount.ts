import {
  fullPageSurfaceProps,
  type CatalogApplication,
  type HostBridge,
  type HostContext,
} from "@cadence/plugin-sdk";
import { createApp, type Component } from "vue";
import FullPageSurface from "./FullPageSurface.vue";

export interface FullPageSurfaceMount {
  unmount(): void;
}

/** Mounts one Phoenix-approved full-page surface into an existing DOM root. */
export function mountFullPageSurface(
  root: Element,
  renderer: Component,
  application: CatalogApplication,
  context: HostContext,
  bridge: HostBridge,
): FullPageSurfaceMount {
  if (!root || root.nodeType !== 1) {
    throw new Error("A full-page surface requires an element mount root.");
  }

  const mount = fullPageSurfaceProps(application, context, bridge);
  const app = createApp(FullPageSurface, { renderer, mount });
  app.mount(root);

  return { unmount: () => app.unmount() };
}
