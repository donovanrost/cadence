import { defineComponent, h, shallowRef, type Component, type VNode } from "vue";
import { pageHeaderKey, type MenuItem, type PageAction, type PageHeaderHost } from "./page-header";
import { readPageHeader, type AdmittedHeader } from "./page-header-validation";
import { isRouteId, routeCatalog } from "./routes";

/**
 * A stand-in host for component tests: it admits the page's header exactly as
 * the real host does, and lets a test press its buttons by action id.
 */
export function pageHeaderHarness(route: string) {
  if (!isRouteId(route)) throw new Error(`${route} is not a catalog route`);
  const { layer } = routeCatalog[route];
  const kind = routeCatalog[route].header.kind;
  const current = shallowRef<AdmittedHeader | null>(null);
  const host: PageHeaderHost = {
    route: () => route,
    claim(_owner, routes) {
      if (!routes.includes(route)) throw new Error(`The page did not describe ${route}`);
    },
    update(_owner, value) {
      if (kind === "none") throw new Error(`${route} has no host header`);
      current.value = readPageHeader(value, { kind, layer });
    },
    release() {
      current.value = null;
    },
  };
  const header = () => {
    if (!current.value) throw new Error("The page has not described its header");
    return current.value;
  };
  const actions = (): PageAction[] => {
    const h = header();
    return [...(h.primary ? [h.primary] : []), ...(h.actions ?? []), ...(h.more ?? [])];
  };
  const find = (id: string) => {
    for (const action of actions()) {
      if (action.id === id) return action;
      if ("menu" in action) {
        const item = action.menu.find((entry) => entry.id === id);
        if (item) return item;
      }
    }
    throw new Error(`No header action ${id}`);
  };
  /** Plain controls keyed by action id, standing in for the host's buttons. */
  const control = (action: PageAction | MenuItem): VNode[] => {
    if ("menu" in action) return action.menu.flatMap(control);
    if ("href" in action) return [h("a", { id: action.id, href: action.href }, action.label)];
    return [
      h(
        "button",
        { id: action.id, type: "button", disabled: action.disabled, onClick: () => action.run() },
        action.label,
      ),
    ];
  };
  const controls = () => {
    const admitted = current.value;
    if (!admitted) return [];
    const refresh = admitted.refresh;
    return [
      ...[admitted.primary, ...(admitted.actions ?? []), ...(admitted.more ?? [])].flatMap(
        (action) => (action ? control(action) : []),
      ),
      ...(refresh
        ? [
            h(
              "button",
              { id: "page-header-refresh", type: "button", onClick: () => refresh.run() },
              "Refresh",
            ),
          ]
        : []),
    ];
  };
  const Controls = defineComponent({
    name: "PageHeaderControls",
    setup: () => () => h("div", { id: "page-header-stage" }, controls()),
  });
  /**
   * Wraps a page so its admitted header renders beside it as plain controls;
   * mount the result with the page's props, which pass through unchanged.
   */
  function stage<C extends Component>(page: C): C;
  function stage(page: Component): Component {
    return defineComponent({
      name: "PageHeaderStage",
      inheritAttrs: false,
      provide: { [pageHeaderKey as symbol]: host },
      // The controls mount after the page, so its header is already described.
      setup:
        (_props, { attrs }) =>
        () => [h(page, attrs), h(Controls)],
    });
  }
  return {
    /** Pass as `global: { provide }` when mounting. */
    provide: { [pageHeaderKey as symbol]: host },
    stage,
    header,
    async refresh() {
      const refresh = header().refresh;
      if (!refresh) throw new Error("The page has no refresh");
      await refresh.run();
    },
    async run(id: string) {
      const action = find(id);
      if (!("run" in action)) throw new Error(`${id} is not a command`);
      await action.run();
    },
    href(id: string): string {
      const action = find(id);
      if (!("href" in action)) throw new Error(`${id} is not a link`);
      return action.href;
    },
    has: (id: string) => actions().some((action) => action.id === id),
  };
}
