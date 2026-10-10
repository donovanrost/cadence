import { isRouteId, routeCatalog } from "@cadence/plugin-sdk/routes";

export type Crumb = { label: string; href?: string };
type Named = { display_name?: string | null } | null | undefined;
export type TrailContext = { organization?: Named; mission?: Named; spacecraft?: Named };

const mission = "/missions/:mission_id";
const spacecraft = "/missions/:mission_id/spacecraft/:spacecraft_id";

/** What a route above the page is called in the trail, or null to leave it out. */
function ancestor(pattern: string, context: TrailContext): string | null {
  if (pattern === mission) return context.mission?.display_name || null;
  if (pattern === spacecraft) return context.spacecraft?.display_name || null;
  // Scope roots are the trail's first crumb; records above the page are unnamed in the catalog.
  if (pattern === "/missions" || pattern === "/admin" || !isRouteId(pattern)) return null;
  const route = routeCatalog[pattern];
  return route.header.kind === "collection" ? route.title : null;
}

/**
 * The host's breadcrumb trail: the scope root, then every catalog route above
 * this one (so a record links back to its list), ending at the page itself.
 */
export function breadcrumbTrail(
  route: { path: string; scope: string },
  path: string,
  context: TrailContext,
  title: string,
): Crumb[] {
  const items: Crumb[] = [];
  if (route.scope === "admin") items.push({ label: "Platform", href: "/admin" });
  else if (route.scope === "user") items.push({ label: "Account" });
  else items.push({ label: context.organization?.display_name || "Organization", href: "/" });
  const patterns = route.path.split("/");
  const segments = path.split("/");
  if (patterns.length === segments.length)
    for (let depth = 2; depth < patterns.length; depth++) {
      const label = ancestor(patterns.slice(0, depth).join("/"), context);
      if (label) items.push({ label, href: segments.slice(0, depth).join("/") });
    }
  items.push({ label: title });
  return items;
}
