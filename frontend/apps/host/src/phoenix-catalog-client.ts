import {
  assertFrontendApplicationCatalog,
  type CatalogApplication,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";

export interface PhoenixHostConfig {
  applicationKey: string;
  surfaceId: string;
  spacecraftId?: string;
  missionId: string;
  catalogUrl: string;
  fallbackHref: string;
}

export interface PhoenixCatalogRequestOptions {
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
}

export interface PhoenixContextRequest {
  missionId: string;
  spacecraftId?: string;
}

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

  const context = catalog.session.context;
  const expectedScope = config.spacecraftId === undefined ? "mission" : "spacecraft";
  if (
    context.scope !== expectedScope ||
    context.missionId !== config.missionId ||
    context.spacecraftId !== (config.spacecraftId ?? null)
  ) {
    throw new Error("The application catalog is not scoped to the requested context.");
  }

  return catalog;
}

export function selectPhoenixApplication(
  catalog: FrontendApplicationCatalog,
  config: Pick<PhoenixHostConfig, "applicationKey" | "surfaceId" | "spacecraftId">,
): CatalogApplication {
  assertSelectionContext(config);
  const expectedScope = config.spacecraftId === undefined ? "mission" : "spacecraft";
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
  context: PhoenixContextRequest | string,
  baseUrl = currentOrigin(),
): string {
  const request = typeof context === "string" ? { missionId: context } : context;
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

  target.searchParams.set("mission_id", request.missionId);
  if (request.spacecraftId !== undefined) {
    target.searchParams.set("spacecraft_id", request.spacecraftId);
  } else target.searchParams.delete("spacecraft_id");
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

  if (!nonEmptyString(config.missionId)) {
    throw new Error("The Phoenix host requires a mission id.");
  }

  if (!nonEmptyString(config.catalogUrl)) {
    throw new Error("The Phoenix host requires a catalog URL.");
  }

  if (!nonEmptyString(config.fallbackHref)) {
    throw new Error("The Phoenix host requires a Phoenix fallback href.");
  }

  assertContextRequest(config);
}

function assertSelectionContext(
  config: Pick<PhoenixHostConfig, "applicationKey" | "surfaceId" | "spacecraftId">,
): void {
  if (config.spacecraftId !== undefined && !nonEmptyString(config.spacecraftId)) {
    throw new Error("The Phoenix host requires a non-empty spacecraft id when provided.");
  }
}

function assertContextRequest(context: PhoenixContextRequest): void {
  if (!nonEmptyString(context.missionId)) {
    throw new Error("The Phoenix host requires a mission id.");
  }

  if (context.spacecraftId !== undefined && !nonEmptyString(context.spacecraftId)) {
    throw new Error("The Phoenix host requires a non-empty spacecraft id when provided.");
  }
}

function currentOrigin(): string {
  return typeof window === "undefined" ? "http://localhost/" : window.location.origin;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
