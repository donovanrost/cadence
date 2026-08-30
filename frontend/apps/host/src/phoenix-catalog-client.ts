import {
  assertFrontendApplicationCatalog,
  type CatalogApplication,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";

export const COMMS_OVERVIEW_APPLICATION_KEY = "comms_overview" as const;

export interface PhoenixHostConfig {
  missionId: string;
  catalogUrl: string;
}

export interface PhoenixCatalogRequestOptions {
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
}

export async function loadPhoenixMissionCatalog(
  config: PhoenixHostConfig,
  options: PhoenixCatalogRequestOptions = {},
): Promise<FrontendApplicationCatalog> {
  const fetcher = options.fetch ?? globalThis.fetch;
  const url = phoenixCatalogUrl(config.catalogUrl, config.missionId, options.baseUrl);
  const response = await fetcher(url, { credentials: "same-origin", cache: "no-store" });

  if (!response.ok) {
    throw new Error(`The mission application catalog returned HTTP ${response.status}.`);
  }

  const catalog: unknown = await response.json();
  assertFrontendApplicationCatalog(catalog);

  const context = catalog.session.context;
  if (context.scope !== "mission" || context.missionId !== config.missionId) {
    throw new Error("The mission application catalog is not scoped to the active mission.");
  }

  return catalog;
}

export function selectCommsOverviewApplication(
  catalog: FrontendApplicationCatalog,
): CatalogApplication {
  const application = catalog.applications.find(
    ({ applicationKey }) => applicationKey === COMMS_OVERVIEW_APPLICATION_KEY,
  );

  if (!application) {
    throw new Error("The mission application catalog does not provide comms_overview.");
  }

  if (
    application.applicationVersion !== 1 ||
    application.package.packageId !== "cadence.comms_overview" ||
    application.package.version !== 1 ||
    application.surface.surfaceId !== "overview" ||
    application.surface.version !== 1 ||
    application.surface.purpose !== "overview" ||
    application.surface.scope !== "mission" ||
    application.surface.dataContract.id !== "cadence.comms.overview" ||
    application.surface.dataContract.version !== 1 ||
    application.surface.actions.length !== 0 ||
    application.surface.renderer.exposedModule !== "./Application" ||
    application.release.federation !== "module_federation" ||
    application.release.remoteName !== "cadence_comms_overview" ||
    application.release.exposedModule !== "./Application"
  ) {
    throw new Error("The mission catalog comms_overview application contract is invalid.");
  }

  return application;
}

export function phoenixCatalogUrl(
  catalogUrl: string,
  missionId: string,
  baseUrl = currentOrigin(),
): string {
  if (!nonEmptyString(missionId)) throw new Error("The Phoenix host requires a mission id.");

  const base = new URL(baseUrl);
  const target = new URL(catalogUrl, base);
  if (target.origin !== base.origin) {
    throw new Error("The Phoenix application catalog must use the same origin as the host.");
  }

  target.searchParams.set("mission_id", missionId);
  target.hash = "";
  return catalogUrl.startsWith("/") && !catalogUrl.startsWith("//")
    ? `${target.pathname}${target.search}`
    : target.toString();
}

function currentOrigin(): string {
  return typeof window === "undefined" ? "http://localhost/" : window.location.origin;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
