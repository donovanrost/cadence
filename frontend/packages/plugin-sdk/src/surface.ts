import type { CatalogApplication } from "./catalog";
import type { HostBridge, HostContext } from "./bridge";
import {
  assertCompatibleManifest,
  type FederatedSurfaceDefinition,
  type FirstPartyApplicationManifest,
} from "./manifest";

/** Props shared by every full-page first-party surface renderer. */
export interface FullPageSurfaceProps {
  application: CatalogApplication;
  surface: FederatedSurfaceDefinition;
  context: HostContext;
  bridge: HostBridge;
}

/** A remote contribution is metadata plus a renderer entry owned by its app. */
export interface ApplicationContribution<TModule = unknown> {
  manifest: FirstPartyApplicationManifest;
  load: () => Promise<TModule> | TModule;
}

/**
 * Declares one first-party application contribution at the remote boundary.
 * Catalog admission remains Phoenix-owned; this only validates the renderer's
 * self-description before a remote exposes it.
 */
export function defineApplicationContribution<TContribution extends ApplicationContribution>(
  contribution: TContribution,
): TContribution {
  assertCompatibleManifest(contribution.manifest);
  if (typeof contribution.load !== "function") {
    throw new Error("Application contribution must provide a loader.");
  }
  return contribution;
}

/**
 * Selects one complete surface from a host-approved application without
 * inventing route, auth, or query/action authority in the remote.
 */
export function fullPageSurfaceProps(
  application: CatalogApplication,
  context: HostContext,
  bridge: HostBridge,
): FullPageSurfaceProps {
  const surface = application.surface;
  if (surface.placement !== "application_workspace") {
    throw new Error("A full-page surface must use application_workspace placement.");
  }
  if (surface.scope !== context.scope) {
    throw new Error("A full-page surface must match the active host context.");
  }
  return { application, surface, context, bridge };
}
