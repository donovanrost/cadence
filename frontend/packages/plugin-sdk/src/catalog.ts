import { isHostContext, type HostContext } from "./bridge";
import {
  APPLICATION_HOST_CONTRACT,
  assertCompatibleManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedApplicationModule,
  type FederatedSurfaceDefinition,
} from "./manifest";

export const FRONTEND_APPLICATION_CATALOG_SCHEMA =
  "cadence.first-party-frontend-catalog.v1" as const;

export type FederationTransport = "module_federation" | "native_federation";

export interface FederatedApplicationRelease {
  federation: FederationTransport;
  releaseId: string;
  remoteName: string;
  manifestUrl: string;
  exposedModule: string;
}

export interface CatalogApplication {
  applicationKey: string;
  applicationVersion: number;
  displayName: string;
  description: string;
  package: {
    packageId: string;
    version: number;
  };
  surface: FederatedSurfaceDefinition;
  release: FederatedApplicationRelease;
}

export interface HostSessionDescriptor {
  sessionId: string;
  csrfToken: string;
  bridgeBaseUrl: string;
  context: HostContext;
}

export interface FrontendApplicationCatalog {
  schema: typeof FRONTEND_APPLICATION_CATALOG_SCHEMA;
  hostContract: typeof APPLICATION_HOST_CONTRACT;
  generatedAt: string;
  session: HostSessionDescriptor;
  applications: readonly CatalogApplication[];
}

export function assertFrontendApplicationCatalog(
  value: unknown,
): asserts value is FrontendApplicationCatalog {
  if (
    !isRecord(value) ||
    value.schema !== FRONTEND_APPLICATION_CATALOG_SCHEMA ||
    value.hostContract !== APPLICATION_HOST_CONTRACT ||
    !validDateTime(value.generatedAt) ||
    !validSession(value.session) ||
    !Array.isArray(value.applications) ||
    value.applications.length === 0
  ) {
    throw new Error("The frontend application catalog is invalid.");
  }

  const applicationKeys = new Set<string>();
  const remoteNames = new Set<string>();

  for (const application of value.applications) {
    if (!validCatalogApplication(application)) {
      throw new Error("The frontend application catalog contains an invalid application.");
    }

    if (applicationKeys.has(application.applicationKey)) {
      throw new Error("The frontend application catalog contains a duplicate application key.");
    }

    if (remoteNames.has(application.release.remoteName)) {
      throw new Error("The frontend application catalog contains a duplicate remote name.");
    }

    applicationKeys.add(application.applicationKey);
    remoteNames.add(application.release.remoteName);
  }
}

export function assertReleaseMatchesModule(
  application: CatalogApplication,
  remote: unknown,
): asserts remote is FederatedApplicationModule {
  if (!isRecord(remote) || !("manifest" in remote) || !("default" in remote)) {
    throw new Error("The federated release did not expose an application module.");
  }

  assertCompatibleManifest(remote.manifest);
  const manifest = remote.manifest;
  const surface = manifest.surfaces.find(
    ({ surfaceId }) => surfaceId === application.surface.surfaceId,
  );

  if (
    manifest.application.applicationKey !== application.applicationKey ||
    manifest.application.version !== application.applicationVersion ||
    manifest.package.packageId !== application.package.packageId ||
    manifest.package.version !== application.package.version ||
    !surface ||
    surface.version !== application.surface.version ||
    surface.dataContract.id !== application.surface.dataContract.id ||
    surface.dataContract.version !== application.surface.dataContract.version ||
    surface.renderer.exposedModule !== application.release.exposedModule
  ) {
    throw new Error(
      `Release ${application.release.releaseId} does not match the host-approved application contract.`,
    );
  }
}

function validCatalogApplication(value: unknown): value is CatalogApplication {
  return (
    isRecord(value) &&
    nonEmptyString(value.applicationKey) &&
    positiveInteger(value.applicationVersion) &&
    nonEmptyString(value.displayName) &&
    nonEmptyString(value.description) &&
    validPackage(value.package) &&
    validSurface(value.surface) &&
    validRelease(value.release)
  );
}

function validSession(value: unknown): value is HostSessionDescriptor {
  return (
    isRecord(value) &&
    nonEmptyString(value.sessionId) &&
    nonEmptyString(value.csrfToken) &&
    validBridgeBaseUrl(value.bridgeBaseUrl) &&
    isHostContext(value.context)
  );
}

function validPackage(value: unknown): value is CatalogApplication["package"] {
  return isRecord(value) && nonEmptyString(value.packageId) && positiveInteger(value.version);
}

function validSurface(value: unknown): value is FederatedSurfaceDefinition {
  if (!isRecord(value)) return false;

  try {
    assertCompatibleManifest({
      schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
      hostContract: APPLICATION_HOST_CONTRACT,
      package: { packageId: "catalog.validation", version: 1, trust: "first_party" },
      compatibility: {
        cadenceApplicationContract: 1,
        cadenceSurfaceContract: 1,
        cadenceFederatedRendererContract: 1,
        cadenceThemeContract: 1,
      },
      application: {
        applicationKey: "catalog_validation",
        version: 1,
        displayName: "Catalog validation",
        description: "Validates one catalog surface.",
        installableScopes: [value.scope],
      },
      surfaces: [value],
    });
    return true;
  } catch {
    return false;
  }
}

function validRelease(value: unknown): value is FederatedApplicationRelease {
  return (
    isRecord(value) &&
    (value.federation === "module_federation" || value.federation === "native_federation") &&
    nonEmptyString(value.releaseId) &&
    validRemoteName(value.remoteName) &&
    validManifestUrl(value.manifestUrl) &&
    typeof value.exposedModule === "string" &&
    /^\.\/[A-Za-z][A-Za-z0-9_-]*$/.test(value.exposedModule)
  );
}

function validRemoteName(value: unknown): value is string {
  return typeof value === "string" && /^[a-z][a-z0-9_]*$/.test(value);
}

function validManifestUrl(value: unknown): value is string {
  if (typeof value !== "string") return false;
  if (value.startsWith("/") && !value.startsWith("//")) return true;

  try {
    const url = new URL(value);
    return url.protocol === "https:" || (url.protocol === "http:" && loopback(url.hostname));
  } catch {
    return false;
  }
}

function validBridgeBaseUrl(value: unknown): value is string {
  return typeof value === "string" && value.startsWith("/") && !value.startsWith("//");
}

function validDateTime(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function loopback(hostname: string): boolean {
  return hostname === "127.0.0.1" || hostname === "localhost" || hostname === "[::1]";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function positiveInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) > 0;
}
