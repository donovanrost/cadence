import routes from "../routes.json";
import { createRouter, type RouterHistory } from "vue-router";

type CatalogRoute = (typeof routes)[number];
function normalizeHostRoute(route: CatalogRoute) {
  switch (route.kind) {
    case "application_management":
      if (route.scope === "mission" || route.scope === "spacecraft")
        return { ...route, kind: "application_management" as const, scope: route.scope };
      break;
    case "mission":
      if (route.missionPage)
        return { ...route, kind: "mission" as const, missionPage: route.missionPage };
      break;
    case "spacecraft":
      if (route.spacecraftPage)
        return { ...route, kind: "spacecraft" as const, spacecraftPage: route.spacecraftPage };
      break;
    case "catalog":
      if (route.catalogPage)
        return { ...route, kind: "catalog" as const, catalogPage: route.catalogPage };
      break;
    case "administration":
      if (route.administrationPage)
        return {
          ...route,
          kind: "administration" as const,
          administrationPage: route.administrationPage,
        };
      break;
    case "platform_administration":
      if (route.administrationPage)
        return {
          ...route,
          kind: "platform_administration" as const,
          administrationPage: route.administrationPage,
        };
      break;
    case "organization_module":
      if (route.contribution)
        return { ...route, kind: "organization_module" as const, contribution: route.contribution };
      break;
    case "mission_module":
      if (route.contribution)
        return { ...route, kind: "mission_module" as const, contribution: route.contribution };
      break;
    case "spacecraft_module":
      if (route.contribution)
        return { ...route, kind: "spacecraft_module" as const, contribution: route.contribution };
      break;
    case "ops_module":
      if (route.contribution)
        return { ...route, kind: "ops_module" as const, contribution: route.contribution };
      break;
    case "ops_workspace":
      if (route.workspacePage === "landing" || route.workspacePage === "timeline")
        return { ...route, kind: "ops_workspace" as const, workspacePage: route.workspacePage };
      break;
    case "settings":
      return { ...route, kind: "settings" as const };
    case "notifications":
      return { ...route, kind: "notifications" as const };
    case "activation_approvals":
      return { ...route, kind: "activation_approvals" as const };
    case "administration_diagnostics":
      return { ...route, kind: "administration_diagnostics" as const };
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
const matchers = routes.map((route) => ({
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
    routes: routes.map((route) => ({
      path: route.path,
      name: route.path,
      component: {},
      meta: { host: normalizeHostRoute(route) },
    })),
  });
}

export function shellForRoute(route: Pick<HostRoute, "path" | "scope">) {
  if (route.path === "/missions/:mission_id/ops" || route.path.includes("/ops/")) return "ops";
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
