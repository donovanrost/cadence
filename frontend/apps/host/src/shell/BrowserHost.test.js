import { afterEach, beforeEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory } from "vue-router";
import { h } from "vue";

const transport = vi.hoisted(() => ({ requests: [], pushEvent: vi.fn() }));
vi.mock("live_vue", () => ({ useLiveVue: () => transport }));
vi.mock("./host-browser-history", async () => {
  const { createMemoryHistory } = await import("vue-router");
  return { hostBrowserHistory: createMemoryHistory(), ownBrowserHistory: vi.fn() };
});
import { hostBrowserHistory } from "./host-browser-history";
import BrowserHost from "./BrowserHost.vue";
import { createHostRouter, shellForRoute } from "./host-navigation";
import routes from "../routes.json";

const surface = {
  name: "SurfaceProbe",
  props: ["surface", "navigate"],
  render() {
    return h("div", { id: "surface-probe" });
  },
};
function snapshot(path, mission = null) {
  return {
    path,
    presentation: null,
    error: null,
    context: {
      user: { user_id: "u-1", display_name: "Operator", email: "operator@example.test" },
      organization: { organization_id: "org-1", display_name: "Operations" },
      organizations: [],
      capabilities: [],
      notifications: [],
      unread_count: 0,
      csrf_token: "csrf",
      mission: mission && { mission_id: mission, display_name: mission, slug: mission },
      dashboard_navigation: { starred: [], recent: [] },
      dock_surfaces: [],
    },
  };
}
let wrapper;
beforeEach(() => {
  transport.requests = [];
  transport.pushEvent.mockImplementation((event, payload, reply) =>
    transport.requests.push({ event, payload, reply }),
  );
  window.history.replaceState({}, "", "/missions");
  hostBrowserHistory.replace("/missions");
});
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = "";
  vi.clearAllMocks();
});
async function start() {
  wrapper = mount(BrowserHost, {
    attachTo: document.body,
    props: { snapshot: snapshot("/missions") },
    global: { stubs: { RoutedFederationSurface: surface } },
  });
  await flushPromises();
  return wrapper;
}
async function click(href) {
  const anchor = document.createElement("a");
  anchor.href = href;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  await flushPromises();
}
async function reply(index, value) {
  transport.requests[index].reply({ ok: true, snapshot: value });
  await flushPromises();
}

test("mission entry commits page and sidebar together after authorized context arrives", async () => {
  const app = await start();
  const sidebar = app.get("[data-sidebar-collapsible]").element;
  await click("/missions/mission-a");
  expect(transport.requests[0].payload).toEqual({ path: "/missions/mission-a" });
  expect(app.find('a[href="/missions/mission-a/spacecraft"]').exists()).toBe(false);
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  expect(app.get("[data-sidebar-collapsible]").element).toBe(sidebar);
  expect(app.get('a[href="/missions/mission-a"]').attributes("aria-current")).toBe("page");
  expect(app.getComponent(surface).props("surface")).toMatchObject({
    applicationKey: "mission_catalog",
    surfaceId: "mission_overview",
    missionId: "mission-a",
  });
});

test("late navigation and live-prop responses cannot replace the committed mission", async () => {
  const app = await start();
  await click("/missions/mission-a");
  await click("/missions/mission-b");
  await reply(1, snapshot("/missions/mission-b", "mission-b"));
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  await app.setProps({ snapshot: snapshot("/missions/mission-a", "mission-a") });
  expect(app.getComponent(surface).props("surface").missionId).toBe("mission-b");
  expect(app.find('a[href="/missions/mission-b/spacecraft"]').exists()).toBe(true);
});

test("remote redirects use the same host guard and query parameters cannot replace path identity", async () => {
  const app = await start();
  app.getComponent(surface).props("navigate")(
    "/missions/mission-a/comms/transports/transport-1?mission_id=forged&application_key=forged",
  );
  await flushPromises();
  const path = transport.requests[0].payload.path;
  await reply(0, snapshot(path, "mission-a"));
  expect(app.getComponent(surface).props("surface")).toMatchObject({
    applicationKey: "comms",
    surfaceId: "transport",
    missionId: "mission-a",
    queryParams: { transport_id: "transport-1" },
  });
});

test("denied context preserves the displayed page and reports a recoverable failure", async () => {
  const app = await start();
  await click("/missions/missing");
  transport.requests[0].reply({ ok: false });
  await flushPromises();
  expect(app.getComponent(surface).props("surface").surfaceId).toBe("mission_list");
  expect(app.get("#host-navigation-error").attributes("role")).toBe("alert");
});

test("Back and Forward reenter the guard without replacing the Vue shell", async () => {
  const app = await start();
  const shell = app.element;
  await click("/missions/mission-a/spacecraft");
  await reply(0, snapshot("/missions/mission-a/spacecraft", "mission-a"));
  hostBrowserHistory.go(-1);
  await flushPromises();
  expect(transport.requests[1].payload.path).toBe("/missions");
  await reply(1, snapshot("/missions"));
  hostBrowserHistory.go(1);
  await flushPromises();
  await reply(2, snapshot("/missions/mission-a/spacecraft", "mission-a"));
  expect(app.element).toBe(shell);
  expect(app.getComponent(surface).props("surface").surfaceId).toBe("list");
});

test("every catalog path selects its declared frontend route, including static/dynamic siblings", async () => {
  const router = createHostRouter(createMemoryHistory());
  for (const route of routes) {
    const path = route.path.replace(/:([a-z_]+)/g, (_, name) => `${name}-test`);
    const resolved = router.resolve(path);
    expect(resolved.meta.host, path).toEqual(route);
    expect(shellForRoute(route), path).toBe(
      route.path.includes("/ops/")
        ? "ops"
        : route.scope === "user"
          ? "user_shell"
          : ["mission", "spacecraft"].includes(route.scope)
            ? "mission_sidebar"
            : "sidebar",
    );
  }
});

test("reconnection refreshes the displayed resource rather than the initial transport URL", async () => {
  const app = await start();
  await click("/missions/mission-a");
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  // A LiveView reconnect can resend its original bootstrap snapshot.
  await app.setProps({ snapshot: snapshot("/missions") });
  window.dispatchEvent(new Event("cadence:transport-reconnected"));
  await flushPromises();
  expect(transport.requests[1].payload.path).toBe("/missions/mission-a");
  const refreshed = snapshot("/missions/mission-a", "mission-a");
  refreshed.context.mission.display_name = "Renamed Mission";
  await reply(1, refreshed);
  expect(app.text()).toContain("Renamed Mission");
});

test("admin navigation is selected by the frontend route without server layout metadata", async () => {
  const app = await start();
  await click("/admin/runtime");
  const admin = snapshot("/admin/runtime");
  admin.context.capabilities = ["platform_admin"];
  await reply(0, admin);
  expect(app.get('a[href="/admin/runtime"]').attributes("aria-current")).toBe("page");
  expect(app.find('a[href="/admin/organizations"]').exists()).toBe(true);
  expect(app.find('a[href="/missions"]').exists()).toBe(false);
});
