import routes from "../routes.json";
import { createRouter, type RouterHistory } from "vue-router";

export type HostRoute = (typeof routes)[number];
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
  return matchers.find(({ pattern }) => pattern.test(url.pathname))?.route;
}

export function createHostRouter(history: RouterHistory) {
  return createRouter({
    history,
    routes: routes.map((route) => ({
      path: route.path,
      name: route.path,
      component: {},
      meta: { host: route },
    })),
  });
}

export function shellForRoute(route: HostRoute) {
  if (route.path.includes("/ops/")) return "ops";
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
    const anchor = (event.target as Element | null)?.closest<HTMLAnchorElement>("a[href]");
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
