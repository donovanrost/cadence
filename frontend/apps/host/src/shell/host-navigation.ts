import routes from "../routes.json";
import { createRouter, type RouterHistory } from "vue-router";
import { routeLayer } from "@cadence/plugin-sdk/routes";

type CatalogRoute = (typeof routes)[number];
function normalizeHostRoute(route: CatalogRoute) {
  switch (route.kind) {
    case "ops_module":
      if (route.contribution)
        return { ...route, kind: "ops_module" as const, contribution: route.contribution };
      break;
    case "ops_workspace":
      if (route.workspacePage === "landing" || route.workspacePage === "timeline")
        return { ...route, kind: "ops_workspace" as const, workspacePage: route.workspacePage };
      break;
  }
  return { ...route, kind: "unavailable" as const };
}
export type HostRoute = ReturnType<typeof normalizeHostRoute>;
declare module "vue-router" {
  interface RouteMeta {
    host?: HostRoute;
    snapshot?: import("./host-snapshot").HostSnapshot;
  }
}
// Only Ops pages are served by this router. Other catalog entries (spacecraft, catalog, application
// surfaces) exist only so the components that still render them can type a page header.
const hostRoutes = routes.filter(
  (route) => route.kind === "ops_module" || route.kind === "ops_workspace",
);
const matchers = hostRoutes.map((route) => ({
  route,
  pattern: new RegExp(
    `^${route.path
      .split("/")
      .map((part) => (part.startsWith(":") ? "[^/]+" : part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
      .join("/")}$`,
  ),
}));

export function hostRoute(url: URL) {
  const match = matchers.find(({ pattern }) => pattern.test(url.pathname));
  return match ? normalizeHostRoute(match.route) : undefined;
}

export function createHostRouter(history: RouterHistory) {
  // Each host owns its subscriptions, not the document's shared history. A
  // component remount must release its listeners without disabling its successor.
  const subscriptions = new Set<() => void>();
  let disposed = false;
  const ownedHistory: RouterHistory = {
    ...history,
    get location() {
      return history.location;
    },
    get state() {
      return history.state;
    },
    listen(callback) {
      if (disposed) return () => {};
      const unsubscribe = history.listen(callback);
      const remove = () => {
        unsubscribe();
        subscriptions.delete(remove);
      };
      subscriptions.add(remove);
      return remove;
    },
    destroy() {
      disposed = true;
      for (const remove of subscriptions) remove();
    },
  };
  return createRouter({
    history: ownedHistory,
    routes: hostRoutes.map((route) => ({
      path: route.path,
      name: route.path,
      component: {},
      meta: { host: normalizeHostRoute(route) },
    })),
  });
}

export function shellForRoute(route: Pick<HostRoute, "path" | "scope">) {
  if (routeLayer(route.path) === "ops") return "ops";
  if (route.scope === "user") return "user_shell";
  if (route.scope === "mission" || route.scope === "spacecraft") return "mission_sidebar";
  return "sidebar";
}

/** Adapt plain remote anchors to the host router; session/controller links remain native. */
export function installHostNavigation(
  document: Document,
  location: Pick<Location, "href">,
  navigate: (href: string, replace: boolean) => void,
) {
  const onClick = (event: MouseEvent) => {
    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    const anchor =
      event.target instanceof Element ? event.target.closest<HTMLAnchorElement>("a[href]") : null;
    if (
      !anchor ||
      anchor.hasAttribute("download") ||
      anchor.hasAttribute("data-method") ||
      (anchor.target && anchor.target !== "_self")
    )
      return;
    const current = new URL(location.href);
    const next = new URL(anchor.href, current);
    if (
      next.origin !== current.origin ||
      next.username ||
      next.password ||
      !hostRoute(current) ||
      !hostRoute(next)
    )
      return;
    if (next.pathname === current.pathname && next.search === current.search && next.hash) return;
    event.preventDefault();
    // LiveSocket must not also process historical data-phx-link attributes in remotes.
    event.stopPropagation();
    navigate(next.pathname + next.search + next.hash, anchor.dataset.phxLinkState === "replace");
  };
  // Remote Vue handlers run first; LiveSocket handles links later on window.
  document.addEventListener("click", onClick);
  return () => document.removeEventListener("click", onClick);
}
