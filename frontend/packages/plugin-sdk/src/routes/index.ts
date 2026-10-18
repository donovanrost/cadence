import { routeCatalog } from "./catalog.generated";
import type { ProjectedRoute } from "./project";

export { routeCatalog };
export { routeLayer, type Layer } from "./project";

/** A route in the host catalog, named by its path pattern. */
export type RouteId = keyof typeof routeCatalog;
export type Route<R extends RouteId> = (typeof routeCatalog)[R];
export type RouteQueryKey<R extends RouteId> = Route<R>["queryKeys"][number];
export type RouteHeaderKind<R extends RouteId> = Route<R>["header"]["kind"];
export type RouteLayer<R extends RouteId> = Route<R>["layer"];
/** A route's header policy, widened for code that handles any route. */
export type RouteHeaderPolicy = ProjectedRoute["header"];

type PathParams<P extends string> = P extends `${string}:${infer K}/${infer Rest}`
  ? K | PathParams<`/${Rest}`>
  : P extends `${string}:${infer K}`
    ? K
    : never;
export type RouteParams<R extends RouteId> = PathParams<R>;

declare const hrefBrand: unique symbol;
/** A same-origin link built from the catalog. Only `href()` makes one. */
export type Href = string & { readonly [hrefBrand]: true };

export type RouteQuery<R extends RouteId> = Partial<Record<RouteQueryKey<R>, string | null>>;
type HrefArgs<R extends RouteId> = [RouteParams<R>] extends [never]
  ? [params?: Record<string, never>, query?: RouteQuery<R>]
  : [params: Record<RouteParams<R>, string>, query?: RouteQuery<R>];

export function isRouteId(value: string): value is RouteId {
  return Object.hasOwn(routeCatalog, value);
}

/**
 * Builds a link to a catalog route. Renaming a route, dropping a path param or
 * using a query key the route does not admit is a type error at every caller.
 */
export function href<R extends RouteId>(route: R, ...[params, query]: HrefArgs<R>): Href {
  const values: Record<string, string> = params ?? {};
  const path = route.replace(/:([a-z_]+)/g, (_, name: string) => {
    const value = values[name];
    if (value === undefined || value === "") throw new Error(`Missing route param ${name}`);
    return encodeURIComponent(value);
  });
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {}))
    if (typeof value === "string" && value !== "") search.set(key, value);
  const suffix = search.toString();
  return `${path}${suffix ? `?${suffix}` : ""}` as Href;
}

/**
 * A link the server produced for this page, such as an application surface the
 * host catalog does not list. The server authorized it; this only admits a
 * same-origin path. Prefer `href()` whenever the route is in the catalog.
 */
export function serverHref(value: string): Href {
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  if (!value.startsWith("/") || value.startsWith("//") || /[\u0000-\u001f]/.test(value))
    throw new Error("A server link must be a same-origin path");
  return value as Href;
}
