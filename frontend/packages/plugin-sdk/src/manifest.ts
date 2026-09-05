import type { ApplicationScope } from "./bridge";

export const FEDERATED_APPLICATION_MANIFEST_SCHEMA =
  "cadence.first-party-federated-application.v1" as const;

export const APPLICATION_HOST_CONTRACT = "cadence.application-host.v1" as const;

export type SurfacePurpose =
  | "overview"
  | "configuration"
  | "operations"
  | "activity"
  | "subject_detail";
export type SurfacePlacement = "application_workspace" | "ops_workspace" | "ops_dock";

export interface ContractReference {
  id: string;
  version: number;
}

export interface FederatedSurfaceDefinition {
  surfaceId: string;
  version: number;
  purpose: SurfacePurpose;
  scope: ApplicationScope;
  placement: SurfacePlacement;
  navigation: {
    label: string;
    order: number;
  };
  dataContract: ContractReference;
  actions: readonly string[];
  renderer: {
    kind: "federated-vue";
    exposedModule: string;
  };
}

export interface FirstPartyApplicationManifest {
  schema: typeof FEDERATED_APPLICATION_MANIFEST_SCHEMA;
  hostContract: typeof APPLICATION_HOST_CONTRACT;
  package: {
    packageId: string;
    version: number;
    trust: "first_party";
  };
  compatibility: {
    cadenceApplicationContract: 1;
    cadenceSurfaceContract: 1;
    cadenceFederatedRendererContract: 1;
    cadenceThemeContract: 1;
  };
  application: {
    applicationKey: string;
    version: number;
    displayName: string;
    description: string;
    installableScopes: readonly ApplicationScope[];
  };
  surfaces: readonly FederatedSurfaceDefinition[];
}

export interface FederatedApplicationModule<TComponent = unknown> {
  manifest: FirstPartyApplicationManifest;
  default: TComponent;
}

export function defineApplicationManifest<TManifest extends FirstPartyApplicationManifest>(
  manifest: TManifest,
): TManifest {
  assertCompatibleManifest(manifest);
  return manifest;
}

export function assertCompatibleManifest(
  manifest: unknown,
): asserts manifest is FirstPartyApplicationManifest {
  if (!isRecord(manifest)) {
    throw new Error("Federated application manifest must be an object.");
  }

  if (manifest.schema !== FEDERATED_APPLICATION_MANIFEST_SCHEMA) {
    throw new Error("Federated application manifest schema is not supported.");
  }

  if (manifest.hostContract !== APPLICATION_HOST_CONTRACT) {
    throw new Error("Federated application host contract is not supported.");
  }

  assertPackage(manifest.package);
  assertCompatibility(manifest.compatibility);
  assertApplication(manifest.application);
  assertSurfaces(manifest.surfaces);
}

function assertPackage(value: unknown): void {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.packageId) ||
    !positiveInteger(value.version) ||
    value.trust !== "first_party"
  ) {
    throw new Error("Federated application package declaration is invalid.");
  }
}

function assertCompatibility(value: unknown): void {
  if (
    !isRecord(value) ||
    value.cadenceApplicationContract !== 1 ||
    value.cadenceSurfaceContract !== 1 ||
    value.cadenceFederatedRendererContract !== 1 ||
    value.cadenceThemeContract !== 1
  ) {
    throw new Error("Federated application compatibility declaration is invalid.");
  }
}

function assertApplication(value: unknown): void {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.applicationKey) ||
    !positiveInteger(value.version) ||
    !nonEmptyString(value.displayName) ||
    !nonEmptyString(value.description) ||
    !Array.isArray(value.installableScopes) ||
    value.installableScopes.length === 0 ||
    !value.installableScopes.every(applicationScope)
  ) {
    throw new Error("Federated application declaration is invalid.");
  }
}

function assertSurfaces(value: unknown): void {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("Federated application must contribute at least one surface.");
  }

  const ids = new Set<string>();

  for (const surface of value) {
    if (!isRecord(surface) || !nonEmptyString(surface.surfaceId) || ids.has(surface.surfaceId)) {
      throw new Error("Federated application surfaces must have unique identifiers.");
    }

    ids.add(surface.surfaceId);

    if (
      !positiveInteger(surface.version) ||
      !surfacePurpose(surface.purpose) ||
      !applicationScope(surface.scope) ||
      !surfacePlacement(surface.placement) ||
      !validNavigation(surface.navigation) ||
      !validContractReference(surface.dataContract) ||
      !Array.isArray(surface.actions) ||
      !surface.actions.every(nonEmptyString) ||
      !validRenderer(surface.renderer)
    ) {
      throw new Error(`Federated surface ${surface.surfaceId} is invalid.`);
    }
  }
}

function validNavigation(value: unknown): boolean {
  return isRecord(value) && nonEmptyString(value.label) && Number.isInteger(value.order);
}

function validContractReference(value: unknown): boolean {
  return isRecord(value) && nonEmptyString(value.id) && positiveInteger(value.version);
}

function validRenderer(value: unknown): boolean {
  return isRecord(value) && value.kind === "federated-vue" && nonEmptyString(value.exposedModule);
}

function applicationScope(value: unknown): value is ApplicationScope {
  return (
    value === "organization" ||
    value === "user" ||
    value === "admin" ||
    value === "mission" ||
    value === "spacecraft"
  );
}

function surfacePurpose(value: unknown): value is SurfacePurpose {
  return (
    value === "overview" ||
    value === "configuration" ||
    value === "operations" ||
    value === "activity" ||
    value === "subject_detail"
  );
}

function surfacePlacement(value: unknown): value is SurfacePlacement {
  return value === "application_workspace" || value === "ops_workspace" || value === "ops_dock";
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
