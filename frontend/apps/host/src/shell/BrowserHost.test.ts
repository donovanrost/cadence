import "../module-pages.test-support";
import { nativeElement, required } from "../../../../test-support/mounted-contract";
import {
  fixture as timelineFixture,
  event as timelineEvent,
} from "../ops-workspace/features/timeline/fixtures.test-support";
import { queryKeys as timelineQueryKeys } from "../ops-workspace/features/timeline/contracts";
import { directoryFixture as fleetDirectoryFixture } from "../../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-directory.test-support";
import { afterEach, beforeEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { createMemoryHistory } from "vue-router";
import { defineComponent, h, reactive, nextTick } from "vue";
import type { LiveEventRef } from "live_vue";

type PendingRequest = {
  event: string;
  payload: Record<string, unknown>;
  reply: ((value: unknown) => void) | undefined;
};
const transport = vi.hoisted(() => {
  const requests: PendingRequest[] = [];
  return {
    requests,
    handleEvent: vi.fn<(name: string, callback: (value: unknown) => void) => LiveEventRef>(
      (event, callback) => ({ event, callback: (customEvent) => callback(customEvent.detail) }),
    ),
    removeHandleEvent: vi.fn<(ref: LiveEventRef) => void>(),
    pushEvent:
      vi.fn<
        (event: string, payload: Record<string, unknown>, reply?: (value: unknown) => void) => void
      >(),
  };
});
vi.mock("live_vue", () => ({ useLiveVue: () => transport }));
vi.mock("./host-browser-history", async () => {
  const { createMemoryHistory } = await import("vue-router");
  return { hostBrowserHistory: createMemoryHistory(), ownBrowserHistory: vi.fn() };
});
import { hostBrowserHistory } from "./host-browser-history";
import BrowserHost from "./BrowserHost.vue";
import OpsModulePage from "../ops-workspace/features/module-pages/OpsModulePage.vue";
import SpacecraftPage from "../mission-and-spacecraft/SpacecraftPage.vue";

import { createHostRouter, hostRoute, shellForRoute } from "./host-navigation";
import routes from "../routes.json";
import { monitorFixture } from "../../../../modules/commanding/src/features/mission-commands/monitor.test-support";
import { workspaceFixture as commandWorkspaceFixture } from "../../../../modules/commanding/src/features/workspace/fixtures.test-support";
import { readMonitorQuery } from "../../../../modules/commanding/src/features/mission-commands/monitor-query";
import {
  fixture as explorationFixture,
  selectedFixture as explorationSelectedFixture,
} from "../../../../modules/dashboards-and-exploration/src/features/exploration/fixtures.test-support";

function snapshot(path: string, mission: string | null = null) {
  return {
    path,
    context: {
      version: 1,
      platform_admin: false,
      admin_mode: false,
      nav_context: null,
      nav_item: null,
      user: { user_id: "u-1", display_name: "Operator", email: "operator@example.test" },
      organization: { organization_id: "org-1", display_name: "Operations" },
      organizations: [],
      capabilities: new Array<string>(),
      notifications: [],
      unread_count: 0,
      csrf_token: "csrf",
      mission: mission ? { mission_id: mission, display_name: mission, slug: mission } : null,
      dashboard_navigation: { starred: [], recent: [] },
      dock_surfaces: [],
    },
  };
}
function requestedPath(index: number): string {
  const path = required(transport.requests[index]).payload.path;
  if (typeof path !== "string") throw new Error("Expected a host request path");
  return path;
}
let wrapper: VueWrapper | undefined;
const view = () => required(wrapper);
/**
 * A mission's neutral host page (it renders unavailable without catalog data). L4 removed the
 * mission list, §11c A organization settings and §11c B mission settings and the mission home, so
 * the tests stand on the catalog artifact page (L18), the host's last mission-sidebar page.
 */
const missionPage = (mission: string) => `/missions/${mission}/catalog/artifacts/artifact-1`;
const neutralPath = missionPage("mission-1");
const onNeutral = (root: VueWrapper = view()) =>
  root.findComponent({ name: "CatalogPage" }).exists();
const hostPath = (root: VueWrapper = view()) =>
  root.get("[data-host-path]").attributes("data-host-path");
async function flushHostUpdates() {
  await flushPromises();
  if (wrapper)
    await vi.waitFor(
      () => {
        expect(view().find("[data-host-page-loading]").exists()).toBe(false);
      },
      { timeout: 5_000 },
    );
}
test("compiled command focus and filters retain Ops rails and restore through history", async () => {
  await start();
  const base = "/missions/mission-1/ops/commands";
  const stateAt = (path: string) => {
    const data = monitorFixture();
    data.query = readMonitorQuery(
      Object.fromEntries(new URL(path, "https://cadence.test").searchParams),
    );
    if (data.query.focus_command_id) data.focus = { status: "ready", row: required(data.rows[0]) };
    return {
      ...snapshot(path, "mission-1"),
      ops_page: {
        id: "commanding.monitor",
        slot: "ops.page",
        version: 1,
        status: "ready",
        context: { organizationId: "org-1", missionId: "mission-1" },
        data,
      },
    };
  };
  await click(base);
  await reply(0, stateAt(base));
  const rail = view().get("#ops-nav-rail").element;
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get('[data-command-follow="request-a"]').trigger("click");
  await flushHostUpdates();
  const focused = base + "?focus_command_id=request-a";
  expect(transport.requests[1]).toMatchObject({
    event: "host:context",
    payload: { path: focused },
  });
  await reply(1, stateAt(focused));
  expect(view().get("#command-monitor-focus").attributes("data-followed-command")).toBe(
    "request-a",
  );
  await view().get("#command-monitor-query").setValue("NOOP");
  await view().get("#command-monitor-filters").trigger("submit");
  await flushHostUpdates();
  const filtered = base + "?query=NOOP&focus_command_id=request-a";
  expect(requestedPath(2)).toBe(filtered);
  await reply(2, stateAt(filtered));
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(3)).toBe(focused);
  await reply(3, stateAt(focused));
  expect(
    view().get<HTMLInputElement | HTMLSelectElement>("#command-monitor-query").element.value,
  ).toBe("");
  expect(view().get("#command-monitor-focus").attributes("data-followed-command")).toBe(
    "request-a",
  );
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(transport.requests.every((request) => request.event === "host:context")).toBe(true);
});
test("unavailable command refresh hides stale evidence and permits a read-only retry", async () => {
  await start();
  const path = "/missions/mission-1/ops/commands";
  const page = {
    id: "commanding.monitor",
    slot: "ops.page",
    version: 1,
    status: "ready",
    context: { organizationId: "org-1", missionId: "mission-1" },
    data: monitorFixture(),
  };
  await click(path);
  await reply(0, { ...snapshot(path, "mission-1"), ops_page: page });
  const rail = view().get("#ops-nav-rail").element;
  await view().get("#host-page-refresh").trigger("click");
  await flushHostUpdates();
  await reply(1, {
    ...snapshot(path, "mission-1"),
    ops_page: { ...page, status: "unavailable", data: undefined },
  });
  expect(view().find("[data-command-request]").exists()).toBe(false);
  expect(view().find("#ops-module-unavailable").exists()).toBe(true);
  await view().get("#ops-module-retry").trigger("click");
  await flushHostUpdates();
  expect(transport.requests[2]).toMatchObject({ event: "host:context", payload: { path } });
  await reply(2, { ...snapshot(path, "mission-1"), ops_page: page });
  expect(view().find('[data-command-request="request-a"]').exists()).toBe(true);
  expect(view().get("#ops-nav-rail").element).toBe(rail);
});
test("Explore links its origin dashboard out of the shell, to the console viewer", async () => {
  await start();
  const path = "/missions/mission-1/ops/explore?point_id=HK.voltage&source_dashboard_id=origin";
  const data = { ...explorationFixture(), organization_id: "org-1", mission_id: "mission-1" };
  data.query = Object.fromEntries(new URL(path, "https://cadence.test").searchParams);
  const state = {
    ...snapshot(path, "mission-1"),
    ops_page: {
      id: "dashboards.exploration",
      slot: "ops.page",
      version: 1,
      status: "ready",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data,
    },
  };
  await click(path);
  await reply(0, state);
  const origin = "/missions/mission-1/ops/dashboards/origin";
  // The dashboard viewer left the shell for the console (L8 cutover): the origin link is a plain
  // page load, which the server redirects to the console's viewer; the shell doesn't take it.
  expect(view().get("#exploration-open-origin").attributes("href")).toBe(origin);
  await view().get("#exploration-open-origin").trigger("click");
  await flushHostUpdates();
  expect(transport.requests).toHaveLength(1);
});
test("compiled Explore navigates real query and sample identities through host history", async () => {
  await start();
  const base =
    "/missions/mission-1/ops/explore?point_id=HK.voltage&time_mode=last_1h&source_binding_id=binding-a&source_dashboard_id=origin";
  const stateAt = (path: string) => {
    const data = explorationFixture();
    Object.assign(data, { organization_id: "org-1", mission_id: "mission-1" });
    data.query = Object.fromEntries(new URL(path, "https://cadence.test").searchParams);
    if (data.query.sample_id) data.inspection = explorationSelectedFixture().inspection;
    return {
      ...snapshot(path, "mission-1"),
      ops_page: {
        id: "dashboards.exploration",
        slot: "ops.page",
        version: 1,
        status: "ready",
        context: { organizationId: "org-1", missionId: "mission-1" },
        data,
      },
    };
  };
  await click(base);
  await reply(0, stateAt(base));
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  expect(view().find("#ops-module-unavailable").exists()).toBe(false);
  const rail = view().get("#ops-nav-rail").element;
  await view().get("#exploration-results button").trigger("click");
  await flushHostUpdates();
  const selected = requestedPath(1);
  const query = new URL(selected, "https://cadence.test").searchParams;
  expect(query.get("sample_id")).toBe("sample/one");
  expect(query.get("selected_time")).toBe("2026-09-07T11:59:59.654321Z");
  expect(query.get("from")).toBe("2026-09-07T11:00:00.123456Z");
  expect(query.get("source_binding_id")).toBe("binding-a");
  expect(query.get("selected_data_source_id")).toBe("source-a");
  expect(query.get("selected_source_binding_id")).toBe("binding-a");
  expect(query.has("data_source_id")).toBe(false);
  expect(query.get("source_dashboard_id")).toBe("origin");
  await reply(1, stateAt(selected));
  expect(view().get("#exploration-selection").text()).toContain("sample/one");
  expect(view().get("#exploration-sample-raw_value").text()).toBe('{"adc":1234}');
  expect(view().get("#exploration-sample-receipt").text()).toBe("2026-09-07T11:59:59.654321Z");
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(2)).toBe(base);
  await reply(2, stateAt(base));
  expect(view().find("#exploration-selection").exists()).toBe(false);
  expect(view().find("#exploration-sample-details").exists()).toBe(false);
  await view().get("#exploration-source_binding_id").setValue("binding+b");
  await view().get("#exploration-query").trigger("submit");
  await flushHostUpdates();
  const changed = requestedPath(3);
  expect(new URL(changed, "https://cadence.test").searchParams.get("source_binding_id")).toBe(
    "binding+b",
  );
  const invalid = stateAt(changed);
  invalid.ops_page.data.mission_id = "foreign";
  await reply(3, invalid);
  expect(view().find("#ops-module-unavailable").exists()).toBe(true);
  expect(view().find("#exploration-results").exists()).toBe(false);
  await view().get("#ops-module-retry").trigger("click");
  await flushHostUpdates();
  expect(requestedPath(4)).toBe(changed);
  await reply(4, stateAt(changed));
  expect(
    view().get<HTMLInputElement | HTMLSelectElement>("#exploration-source_binding_id").element
      .value,
  ).toBe("binding+b");
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  await view().get("#host-page-refresh").trigger("click");
  await flushHostUpdates();
  expect(transport.requests).toHaveLength(6);
  await click("/missions/mission-1/ops/dashboards");
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(transport.requests).toHaveLength(6);
  required(required(transport.requests[5]).reply)({ ok: false });
  await flushHostUpdates();
  expect(view().find("#exploration-refresh-failed").exists()).toBe(true);
  expect(view().find("#exploration-results").exists()).toBe(false);
  await view().get("#host-page-refresh").trigger("click");
  await flushHostUpdates();
  const revoked = stateAt(changed);
  revoked.ops_page = { ...revoked.ops_page, status: "unavailable" };
  // @ts-expect-error The malformed producer omits the required page payload.
  delete revoked.ops_page.data;
  await reply(6, revoked);
  expect(view().find("#ops-module-unavailable").exists()).toBe(true);
  expect(view().find("#exploration-results").exists()).toBe(false);
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(transport.requests.every((request) => request.event === "host:context")).toBe(true);
});
beforeEach(() => {
  transport.requests = [];
  transport.pushEvent.mockImplementation((event, payload, reply) =>
    transport.requests.push({ event, payload, reply }),
  );
  window.history.replaceState({}, "", neutralPath);
  hostBrowserHistory.replace(neutralPath);
});
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = "";
  vi.clearAllMocks();
});
async function start() {
  wrapper = mount(BrowserHost, {
    attachTo: document.body,
    props: { snapshot: snapshot(neutralPath, "mission-1") },
  });
  await flushHostUpdates();
  return view();
}
async function click(href: string) {
  const anchor = document.createElement("a");
  anchor.href = href;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  await flushHostUpdates();
}
async function reply(index: number, value: unknown) {
  required(required(transport.requests[index]).reply)({ ok: true, snapshot: value });
  await flushHostUpdates();
}

test("host remounts within the same Vue app and ignores the previous instance's pending reply", async () => {
  const listen = vi.spyOn(hostBrowserHistory, "listen");
  const destroyHistory = vi.spyOn(hostBrowserHistory, "destroy");
  try {
    wrapper = mount(
      defineComponent({
        data: () => ({ revision: 0 }),
        render() {
          return h(BrowserHost, {
            key: this.revision,
            snapshot: snapshot(neutralPath, "mission-1"),
          });
        },
      }),
      { attachTo: document.body },
    );
    await flushHostUpdates();
    expect(onNeutral()).toBe(true);
    await click(missionPage("old-mission"));
    expect(transport.requests).toHaveLength(1);
    await view().setData({ revision: 1 });
    await flushHostUpdates();
    expect(onNeutral()).toBe(true);
    await reply(0, snapshot(missionPage("old-mission"), "old-mission"));
    expect(onNeutral()).toBe(true);
    await click(missionPage("current-mission"));
    expect(transport.requests).toHaveLength(2);
    await reply(1, snapshot(missionPage("current-mission"), "current-mission"));
    expect(hostPath()).toBe(missionPage("current-mission"));
    hostBrowserHistory.go(-1);
    await flushHostUpdates();
    expect(transport.requests).toHaveLength(3);
    await reply(2, snapshot(neutralPath, "mission-1"));
    expect(onNeutral()).toBe(true);
    expect(listen).toHaveBeenCalledTimes(2);
    expect(destroyHistory).not.toHaveBeenCalled();
  } finally {
    listen.mockRestore();
    destroyHistory.mockRestore();
  }
});

test("late navigation and live-prop responses cannot replace the committed mission", async () => {
  const app = await start();
  await click(missionPage("mission-a"));
  await click(missionPage("mission-b"));
  await reply(1, snapshot(missionPage("mission-b"), "mission-b"));
  await reply(0, snapshot(missionPage("mission-a"), "mission-a"));
  await app.setProps({ snapshot: snapshot(missionPage("mission-a"), "mission-a") });
  expect(hostPath(app)).toBe(missionPage("mission-b"));
  expect(app.find('a[href="/missions/mission-b/spacecraft"]').exists()).toBe(true);
});

test("compiled contact navigation use the same host guard and query parameters cannot replace path identity", async () => {
  const app = await start();
  await click("/missions/mission-a/ops/contacts/records/contact-2");
  await reply(0, snapshot("/missions/mission-a/ops/contacts/records/contact-2", "mission-a"));
  required(app.getComponent(OpsModulePage).props("navigate"))(
    "/missions/mission-a/ops/contacts/records/contact-1?mission_id=forged&contact_id=forged&application_key=forged",
  );
  await flushHostUpdates();
  const path = requestedPath(1);
  await reply(1, snapshot(path, "mission-a"));
  expect(app.getComponent(OpsModulePage).props("contributionId")).toBe("planning.contact-record");
  expect(app.getComponent(OpsModulePage).props("context")).toMatchObject({
    missionId: "mission-a",
    resourceId: "contact-1",
  });
});

test("denied context preserves the displayed page and reports a recoverable failure", async () => {
  const app = await start();
  await click(missionPage("missing"));
  required(required(transport.requests[0]).reply)({ ok: false });
  await flushHostUpdates();
  expect(onNeutral(app)).toBe(true);
  expect(app.get("#host-navigation-error").attributes("role")).toBe("alert");
});

test("Back and Forward reenter the guard without replacing the Vue shell", async () => {
  const app = await start();
  const shell = required(nativeElement(app.element));
  const spacecraftPath = "/missions/mission-a/spacecraft/sc-1";
  await click(spacecraftPath);
  await reply(0, snapshot(spacecraftPath, "mission-a"));
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(1)).toBe(neutralPath);
  await reply(1, snapshot(neutralPath, "mission-1"));
  hostBrowserHistory.go(1);
  await flushHostUpdates();
  await reply(2, snapshot(spacecraftPath, "mission-a"));
  expect(app.element).toBe(shell);
  expect(app.getComponent(SpacecraftPage).props("page")).toBe("spacecraft_configuration");
});

// Application surfaces are served by the Phoenix application host, not this router.
const hostRoutes = routes.filter((route) => route.kind !== "application_surface");
test("every catalog path selects its declared frontend route, including static/dynamic siblings", async () => {
  const router = createHostRouter(createMemoryHistory());
  for (const route of hostRoutes) {
    const path = route.path.replace(/:([a-z_]+)/g, (_, name) => `${name}-test`);
    const resolved = router.resolve(path);
    expect(resolved.meta.host, path).toEqual(route);
    expect(shellForRoute(route), path).toBe(
      route.path === "/missions/:mission_id/ops" || route.path.includes("/ops/")
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
  await click(missionPage("mission-a"));
  await reply(0, snapshot(missionPage("mission-a"), "mission-a"));
  // A LiveView reconnect can resend its original bootstrap snapshot.
  await app.setProps({ snapshot: snapshot(neutralPath, "mission-1") });
  window.dispatchEvent(new Event("cadence:transport-reconnected"));
  await flushHostUpdates();
  expect(requestedPath(1)).toBe(missionPage("mission-a"));
  const refreshed = snapshot(missionPage("mission-a"), "mission-a");
  required(refreshed.context.mission).display_name = "Renamed Mission";
  await reply(1, refreshed);
  expect(app.text()).toContain("Renamed Mission");
});

function fleetSnapshot(path: string) {
  const data = fleetDirectoryFixture();
  data.context = { organization_id: "org-1", mission_id: "mission-1" };
  const params = new URL(path, "https://cadence.test").searchParams;
  data.query.page = Number(params.get("page") ?? 1);
  data.runs.page = data.query.page;
  return {
    ...snapshot(path, "mission-1"),
    ops_page: {
      id: "planning.fleet-directory",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data,
    },
  };
}
test("fleet directory is host-composed and captured reads retain evidence across failures and departure", async () => {
  await start();
  const path = "/missions/mission-1/ops/planning?page=2";
  await click(path);
  await reply(0, fleetSnapshot(path));
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  const rail = view().get("#ops-nav-rail").element;
  await view().get("#host-page-refresh").trigger("click");
  expect(transport.requests[1]).toMatchObject({
    event: "host:ops-page:read",
    payload: {
      path,
      id: "planning.fleet-directory",
      token: "11111111-1111-4111-8111-111111111111",
    },
  });
  const fresh = fleetSnapshot(path).ops_page;
  required(fresh.data.runs.entries[0]).id = "fresh-run";
  await reply(1, fresh);
  expect(view().find("#fleet-run-fresh-run").exists()).toBe(true);
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  await view().get("#host-page-refresh").trigger("click");
  await reply(2, { ...fresh, status: "unavailable" });
  expect(view().find("#fleet-run-fresh-run").exists()).toBe(true);
  await view().get("#host-page-refresh").trigger("click");
  await click(neutralPath);
  await reply(4, snapshot(neutralPath, "mission-1"));
  await reply(3, fresh);
  expect(view().find("#ops-fleet-planning-page").exists()).toBe(false);
  expect(onNeutral()).toBe(true);
});

test("live commanding notices are isolated to the captured path and token and stop after departure", async () => {
  await start();
  const path = "/missions/mission_one/ops/commands/workspace";
  const data = commandWorkspaceFixture();
  const state = snapshot(path, "mission_one");
  state.context.organization.organization_id = "org_one";
  const envelope = {
    id: "commanding.workspace",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: data.directory.context,
    data,
  };
  await click(path);
  await reply(0, { ...state, ops_page: envelope });
  expect(view().find("#command-workspace").exists()).toBe(true);
  await reply(1, envelope); // Initial reconciliation after subscribing.
  await view().get("#workspace-shared-argument-0").setValue("unfinished");
  const handler = required(
    transport.handleEvent.mock.calls.find(([name]) => name === "cadence:ops-page-changed"),
  )[1];
  const notice = { path, id: envelope.id, token: envelope.token };
  for (const invalid of [
    null,
    {},
    { ...notice, path: "/missions/other/ops/commands/workspace" },
    { ...notice, token: "old" },
    { ...notice, id: "other" },
  ])
    handler(invalid);
  await flushPromises();
  expect(transport.requests).toHaveLength(2);
  handler(notice);
  expect(transport.requests[2]).toMatchObject({ event: "host:ops-page:read", payload: notice });
  await reply(2, envelope);
  expect(view().get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe(
    "unfinished",
  );
  await click(neutralPath);
  await reply(3, snapshot(neutralPath, "mission-1"));
  handler(notice);
  await flushPromises();
  expect(transport.requests).toHaveLength(4);
  view().unmount();
  handler(notice);
  expect(transport.requests).toHaveLength(4);
  expect(transport.removeHandleEvent).toHaveBeenCalledWith(
    transport.handleEvent.mock.results[0]?.value,
  );
});

test("core timeline filters, selected evidence and older pages restore through persistent Ops history", async () => {
  await start();
  const base = "/missions/mission-1/ops/timeline";
  const stateAt = (path: string) => {
    const data = timelineFixture();
    const query = new URL(path, "https://cadence.test").searchParams;
    for (const key of timelineQueryKeys) data.query[key] = query.get(key) ?? "";
    data.selected_status = data.query.event_id ? "ready" : "none";
    data.selected = data.query.event_id ? timelineEvent(data.query.event_id) : null;
    data.next_cursor = data.query.before_at
      ? null
      : { at: "2026-09-01T00:00:00Z", id: "mission_event:newer" };
    if (data.query.before_at) data.events = [timelineEvent("mission_event:older")];
    return {
      ...snapshot(path, "mission-1"),
      timeline_page: { version: 1, page: "timeline", status: "ready", context: data.context, data },
    };
  };
  await click(base);
  await reply(0, stateAt(base));
  const rail = view().get("#ops-nav-rail").element;
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#mission-timeline-events a").trigger("click");
  await flushHostUpdates();
  const selectedPath = requestedPath(1);
  expect(new URL(selectedPath, "https://cadence.test").searchParams.get("event_id")).toBe(
    "mission_event:newer",
  );
  await reply(1, stateAt(selectedPath));
  expect(view().get("#timeline-selected-event-id").text()).toBe("mission_event:newer");
  await view().get("#timeline_severity").setValue("warning");
  await view().get("#timeline-filter-form").trigger("submit");
  await flushHostUpdates();
  const filteredPath = requestedPath(2);
  expect(filteredPath).toBe(base + "?severity=warning");
  await reply(2, stateAt(filteredPath));
  await view().get("#timeline-older-events").trigger("click");
  await flushHostUpdates();
  const olderPath = requestedPath(3);
  expect(new URL(olderPath, "https://cadence.test").searchParams.get("before_id")).toBe(
    "mission_event:newer",
  );
  await reply(3, stateAt(olderPath));
  expect(view().find("#timeline-newest-events").exists()).toBe(true);
  expect(view().get("#mission-timeline-events li").attributes("data-event-id")).toBe(
    "mission_event:older",
  );
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(4)).toBe(filteredPath);
  await reply(4, stateAt(filteredPath));
  expect(view().get<HTMLInputElement | HTMLSelectElement>("#timeline_severity").element.value).toBe(
    "warning",
  );
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(transport.requests.every((request) => request.event === "host:context")).toBe(true);
});

const routeComponents = {
  spacecraft: "SpacecraftPage",
  catalog: "CatalogPage",
  ops_module: "OpsModulePage",
};
const routeStubs = Object.fromEntries(
  [...Object.values(routeComponents), "WorkspaceLanding", "TimelinePage"].map((name) => [
    name,
    {
      name,
      inheritAttrs: false,
      render: () => h("div", { "data-route-component": name }),
    },
  ]),
);
test.each(hostRoutes)("the host handles $path ($kind)", async (entry) => {
  const path = entry.path.replace(/:([a-z_]+)/g, "$1-test");
  const route = required(hostRoute(new URL(path, "https://cadence.test")));
  if (route.kind === "unavailable")
    throw new Error("Catalog route must have a registered page kind");
  const expected =
    route.kind === "ops_workspace"
      ? route.workspacePage === "landing"
        ? "WorkspaceLanding"
        : "TimelinePage"
      : routeComponents[route.kind];
  expect(expected).toBeDefined();
  wrapper = mount(BrowserHost, {
    props: { snapshot: snapshot(path, path.includes("/missions/") ? "mission_id-test" : null) },
    global: { stubs: routeStubs },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  expect(view().get("[data-route-component]").attributes("data-route-component")).toBe(expected);
});

test("an unrecognized catalog kind is contained by the host", async () => {
  const route = required(
    routes.find((route) => route.path === "/missions/:mission_id/catalog/artifacts/:artifact_id"),
  );
  const kind = route.kind;
  try {
    route.kind = "unsupported-test-kind";
    wrapper = mount(BrowserHost, {
      props: { snapshot: snapshot(neutralPath, "mission-1") },
      global: { stubs: routeStubs },
    });
    await flushHostUpdates();
    expect(view().get("#host-route-unavailable").attributes("role")).toBe("alert");
    expect(view().find("[data-route-component]").exists()).toBe(false);
  } finally {
    route.kind = kind;
  }
});

test("nested LiveVue patches pass through snapshot admission", async () => {
  const state = reactive(snapshot(neutralPath, "mission-1"));
  wrapper = mount(BrowserHost, { props: { snapshot: state } });
  await flushPromises();
  state.context.organization.display_name = "Patched organization";
  await nextTick();
  expect(wrapper.text()).toContain("Patched organization");
});
