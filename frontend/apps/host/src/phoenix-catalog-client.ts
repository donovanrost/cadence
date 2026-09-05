import {
  assertFrontendApplicationCatalog,
  type ApplicationScope,
  type CatalogApplication,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";
import { assertKnownFirstPartyIdentity } from "./first-party-composition";

interface PhoenixHostConfigBase {
  applicationKey: string;
  surfaceId: string;
  catalogUrl: string;
  fallbackHref: string;
  hostScope?: ApplicationScope;
  organizationId?: string;
  userId?: string;
  missionId?: string;
  spacecraftId?: string;
}

/**
 * Route configuration is a tagged union. The optional fields in the base keep
 * old mission/spacecraft callers source-compatible; assertPhoenixHostConfig
 * applies the same fail-closed rules at the runtime/DOM boundary.
 */
export type PhoenixHostConfig = PhoenixHostConfigBase &
  (
    | { hostScope: "organization"; organizationId: string }
    | { hostScope: "user"; userId: string }
    | { hostScope: "admin" }
    | { hostScope: "mission"; missionId: string; spacecraftId?: never }
    | { hostScope: "spacecraft"; missionId: string; spacecraftId: string }
    | { hostScope?: undefined; missionId: string; spacecraftId?: string }
  );

export interface PhoenixCatalogRequestOptions {
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
}

type TaggedPhoenixContextRequest =
  | { scope: "organization"; organizationId: string }
  | { scope: "user"; userId: string }
  | { scope: "admin" }
  | { scope: "mission"; missionId: string }
  | { scope: "spacecraft"; missionId: string; spacecraftId: string };

interface LegacyPhoenixContextRequest {
  missionId: string;
  spacecraftId?: string;
}

export type PhoenixContextRequest = TaggedPhoenixContextRequest | LegacyPhoenixContextRequest;

export async function loadPhoenixApplicationCatalog(
  config: PhoenixHostConfig,
  options: PhoenixCatalogRequestOptions = {},
): Promise<FrontendApplicationCatalog> {
  assertPhoenixHostConfig(config);

  const fetcher = options.fetch ?? globalThis.fetch;
  if (typeof fetcher !== "function") {
    throw new Error("The Phoenix application host cannot fetch its catalog.");
  }

  const url = phoenixCatalogUrl(config.catalogUrl, config, options.baseUrl);
  const response = await fetcher(url, { credentials: "same-origin", cache: "no-store" });

  if (!response.ok) {
    throw new Error(`The application catalog returned HTTP ${response.status}.`);
  }

  const catalog: unknown = await response.json();
  assertFrontendApplicationCatalog(catalog);
  catalog.applications.forEach(assertKnownFirstPartyIdentity);

  const context = catalog.session.context;
  if (!matchesPhoenixContext(context, contextRequest(config))) {
    throw new Error("The application catalog is not scoped to the requested context.");
  }

  return catalog;
}

export function selectPhoenixApplication(
  catalog: FrontendApplicationCatalog,
  config: Pick<
    PhoenixHostConfig,
    "applicationKey" | "surfaceId" | "hostScope" | "organizationId" | "userId" | "missionId" | "spacecraftId"
  >,
): CatalogApplication {
  assertSelectionContext(config);
  const expectedScope = scopeFromConfig(config);
  const application = catalog.applications.find(
    ({ applicationKey }) => applicationKey === config.applicationKey,
  );

  if (!application) {
    throw new Error(
      `The application catalog does not provide requested application "${config.applicationKey}".`,
    );
  }

  if (application.surface.surfaceId !== config.surfaceId) {
    throw new Error(
      `The application catalog does not provide requested surface "${config.surfaceId}" for application "${config.applicationKey}".`,
    );
  }

  if (application.surface.scope !== expectedScope) {
    throw new Error(
      `The requested application surface is not approved for ${expectedScope} context.`,
    );
  }

  if (application.surface.renderer.exposedModule !== application.release.exposedModule) {
    throw new Error("The selected application release does not match its surface renderer module.");
  }

  return application;
}

export function phoenixCatalogUrl(
  catalogUrl: string,
  context: PhoenixContextRequest | PhoenixHostConfig | string,
  baseUrl = currentOrigin(),
): string {
  const { legacy, request } = normalizeContextRequest(context);
  assertContextRequest(request);

  if (!nonEmptyString(catalogUrl)) {
    throw new Error("The Phoenix host requires a catalog URL.");
  }

  let base: URL;
  let target: URL;

  try {
    base = new URL(baseUrl);
    target = new URL(catalogUrl, base);
  } catch {
    throw new Error("The Phoenix application catalog URL is invalid.");
  }

  if (target.origin !== base.origin) {
    throw new Error("The Phoenix application catalog must use the same origin as the host.");
  }

  if (!legacy) target.searchParams.set("scope", request.scope);
  target.searchParams.delete("organization_id");
  target.searchParams.delete("user_id");
  target.searchParams.delete("mission_id");
  target.searchParams.delete("spacecraft_id");
  if (request.scope === "organization") {
    target.searchParams.set("organization_id", request.organizationId);
  } else if (request.scope === "user") {
    target.searchParams.set("user_id", request.userId);
  } else if (request.scope === "mission") {
    target.searchParams.set("mission_id", request.missionId);
  } else if (request.scope === "spacecraft") {
    target.searchParams.set("mission_id", request.missionId);
    target.searchParams.set("spacecraft_id", request.spacecraftId);
  }
  target.hash = "";

  return catalogUrl.startsWith("/") && !catalogUrl.startsWith("//")
    ? `${target.pathname}${target.search}`
    : target.toString();
}

function assertPhoenixHostConfig(config: PhoenixHostConfig): void {
  if (!nonEmptyString(config.applicationKey)) {
    throw new Error("The Phoenix host requires an application key.");
  }

  if (!nonEmptyString(config.surfaceId)) {
    throw new Error("The Phoenix host requires a surface id.");
  }

  if (!nonEmptyString(config.catalogUrl)) {
    throw new Error("The Phoenix host requires a catalog URL.");
  }

  if (!nonEmptyString(config.fallbackHref)) {
    throw new Error("The Phoenix host requires a Phoenix fallback href.");
  }

  const context = contextRequest(config);
  assertContextRequest(context);
}

function assertSelectionContext(
  config: Pick<
    PhoenixHostConfig,
    "applicationKey" | "surfaceId" | "hostScope" | "organizationId" | "userId" | "missionId" | "spacecraftId"
  >,
): void {
  contextRequest(config);
}

function assertContextRequest(context: TaggedPhoenixContextRequest): void {
  switch (context.scope) {
    case "organization":
      if (!nonEmptyString(context.organizationId) || "userId" in context || "missionId" in context || "spacecraftId" in context) {
        throw new Error("The Phoenix host organization context is invalid.");
      }
      return;
    case "user":
      if (!nonEmptyString(context.userId) || "organizationId" in context || "missionId" in context || "spacecraftId" in context) {
        throw new Error("The Phoenix host user context is invalid.");
      }
      return;
    case "admin":
      if ("organizationId" in context || "userId" in context || "missionId" in context || "spacecraftId" in context) {
        throw new Error("The Phoenix host admin context is invalid.");
      }
      return;
    case "mission":
      if (!nonEmptyString(context.missionId) || "organizationId" in context || "userId" in context || "spacecraftId" in context) {
        throw new Error("The Phoenix host mission context is invalid.");
      }
      return;
    case "spacecraft":
      if (!nonEmptyString(context.missionId) || !nonEmptyString(context.spacecraftId) || "organizationId" in context || "userId" in context) {
        throw new Error("The Phoenix host spacecraft context is invalid.");
      }
      return;
  }
}

function contextRequest(config: {
  hostScope?: ApplicationScope;
  organizationId?: string;
  userId?: string;
  missionId?: string;
  spacecraftId?: string;
}): TaggedPhoenixContextRequest {
  const scope = config.hostScope ?? (config.spacecraftId === undefined ? "mission" : "spacecraft");

  switch (scope) {
    case "organization":
      if (!nonEmptyString(config.organizationId) || config.userId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix host organization context is invalid.");
      }
      return { scope, organizationId: config.organizationId };
    case "user":
      if (!nonEmptyString(config.userId) || config.organizationId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix host user context is invalid.");
      }
      return { scope, userId: config.userId };
    case "admin":
      if (config.organizationId || config.userId || config.missionId || config.spacecraftId) {
        throw new Error("The Phoenix host admin context is invalid.");
      }
      return { scope };
    case "mission":
      if (!nonEmptyString(config.missionId) || config.organizationId || config.userId || config.spacecraftId) {
        throw new Error("The Phoenix host mission context is invalid.");
      }
      return { scope, missionId: config.missionId };
    case "spacecraft":
      if (!nonEmptyString(config.missionId) || !nonEmptyString(config.spacecraftId) || config.organizationId || config.userId) {
        throw new Error("The Phoenix host spacecraft context is invalid.");
      }
      return { scope, missionId: config.missionId, spacecraftId: config.spacecraftId };
    default:
      throw new Error("The Phoenix host scope is invalid.");
  }
}

function normalizeContextRequest(
  context: PhoenixContextRequest | PhoenixHostConfig | string,
): { legacy: boolean; request: TaggedPhoenixContextRequest } {
  if (typeof context === "string") {
    return { legacy: true, request: { scope: "mission", missionId: context } };
  }

  if ("applicationKey" in context) {
    return {
      legacy: context.hostScope === undefined,
      request: contextRequest(context),
    };
  }

  if ("scope" in context) {
    return { legacy: false, request: context };
  }

  if (context.spacecraftId !== undefined) {
    return {
      legacy: true,
      request: {
        scope: "spacecraft",
        missionId: context.missionId,
        spacecraftId: context.spacecraftId,
      },
    };
  }

  return { legacy: true, request: { scope: "mission", missionId: context.missionId } };
}

function scopeFromConfig(config: {
  hostScope?: ApplicationScope;
  organizationId?: string;
  userId?: string;
  missionId?: string;
  spacecraftId?: string;
}): ApplicationScope {
  return contextRequest(config).scope;
}

function matchesPhoenixContext(
  actual: import("@cadence/plugin-sdk").HostContext,
  expected: TaggedPhoenixContextRequest,
): boolean {
  if (actual.scope !== expected.scope) return false;
  switch (expected.scope) {
    case "organization":
      return actual.organizationId === expected.organizationId;
    case "user":
      return actual.scope === "user" && actual.userId === expected.userId;
    case "admin":
      return true;
    case "mission":
      return actual.scope === "mission" && actual.missionId === expected.missionId;
    case "spacecraft":
      return (
        actual.scope === "spacecraft" &&
        actual.missionId === expected.missionId &&
        actual.spacecraftId === expected.spacecraftId
      );
  }
}

function currentOrigin(): string {
  return typeof window === "undefined" ? "http://localhost/" : window.location.origin;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
