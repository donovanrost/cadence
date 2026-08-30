import {
  assertFrontendApplicationCatalog,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";

export interface CatalogRequest {
  release?: "current" | "previous";
  scenario?: string;
}

export async function loadFrontendApplicationCatalog(
  request: CatalogRequest = {},
  fetcher: typeof globalThis.fetch = globalThis.fetch,
): Promise<FrontendApplicationCatalog> {
  const search = new URLSearchParams();
  if (request.release) search.set("release", request.release);
  if (request.scenario) search.set("scenario", request.scenario);

  const suffix = search.size > 0 ? `?${search}` : "";
  const response = await fetcher(`/api/cadence/application-host/v1/catalog${suffix}`, {
    credentials: "same-origin",
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`The frontend application catalog returned HTTP ${response.status}.`);
  }

  const catalog: unknown = await response.json();
  assertFrontendApplicationCatalog(catalog);
  return catalog;
}
