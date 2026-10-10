/**
 * Projects the host route catalog (`apps/host/src/routes.json`, also read by
 * Phoenix) into the typed catalog that pages and the host compile against.
 * Erasable TypeScript only: the generator runs this file directly under Node.
 */
export type HeaderKind = "collection" | "resource" | "none";
/** Ops pages are operators' day-to-day work; management pages maintain records. */
export type Layer = "ops" | "management";
export type ProjectedRoute = {
  kind: string;
  layer: Layer;
  scope: string;
  title: string | null;
  queryKeys: string[];
  header: { kind: HeaderKind; breadcrumbs: boolean; eyebrow: boolean; description: string | null };
};

export type CatalogEntry = {
  path: string;
  kind: string;
  scope: string;
  queryKeys: string[];
  resourceParam?: string;
  pageChrome?: string;
  metadata?: { page_title?: string };
  // A string here: the catalog is JSON, so the kind is checked when projected.
  header?: { kind?: string; breadcrumbs?: boolean; eyebrow?: boolean; description?: string };
};

const headerKinds: readonly string[] = ["collection", "resource", "none"] satisfies HeaderKind[];
const isHeaderKind = (value: string): value is HeaderKind => headerKinds.includes(value);

/** The one rule for a route's layer; the host's shell and the header contracts both read it. */
export function routeLayer(path: string): Layer {
  return path === "/missions/:mission_id/ops" || path.includes("/ops/") ? "ops" : "management";
}

/**
 * A route's header policy: pages that own their identity bar have none, pages
 * about one resource (any path param beyond the mission) must name it, and
 * everything else takes its title from the catalog.
 */
function headerKind(route: CatalogEntry): HeaderKind {
  const declared = route.header?.kind;
  if (declared !== undefined) {
    if (!isHeaderKind(declared))
      throw new Error(`Unknown header kind ${declared} on ${route.path}`);
    return declared;
  }
  if (route.pageChrome === "none") return "none";
  const params = [...route.path.matchAll(/:([a-z_]+)/g)].map((match) => match[1]);
  return route.resourceParam || params.some((param) => param !== "mission_id")
    ? "resource"
    : "collection";
}

export function projectRoutes(catalog: readonly CatalogEntry[]): Record<string, ProjectedRoute> {
  const projected: Record<string, ProjectedRoute> = {};
  for (const route of catalog) {
    if (route.path in projected) throw new Error(`Duplicate route ${route.path}`);
    projected[route.path] = {
      kind: route.kind,
      layer: routeLayer(route.path),
      scope: route.scope,
      title: route.metadata?.page_title ?? null,
      queryKeys: [...route.queryKeys],
      header: {
        kind: headerKind(route),
        breadcrumbs: route.header?.breadcrumbs ?? true,
        eyebrow: route.header?.eyebrow ?? false,
        description: route.header?.description ?? null,
      },
    };
  }
  return projected;
}

export function renderRoutes(catalog: readonly CatalogEntry[]): string {
  return `// Generated from apps/host/src/routes.json by tools/generate-route-types.mjs. Do not edit.
// Run \`corepack pnpm routes:generate\` after changing the route catalog.
export const routeCatalog = ${JSON.stringify(projectRoutes(catalog), null, 2)} as const;
`;
}
