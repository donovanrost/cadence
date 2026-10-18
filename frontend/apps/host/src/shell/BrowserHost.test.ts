import "../module-pages.test-support";
import { containing } from "../../../../test-support/matchers";
import { registrationValues } from "../../../../modules/communications/src/features/provider-accounts/registration.validation";
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
import { spacecraftRoutingSnapshot } from "../../../../modules/communications/src/features/routing/spacecraft-routing.test-support";
import { listFixture } from "../../../../modules/communications/src/features/provider-accounts/provider-accounts.test-support";
import {
  registrationModel,
  validationReceipt,
  receipt,
} from "../../../../modules/communications/src/features/provider-accounts/registration.test-support";
import MissionPage from "../mission-and-spacecraft/MissionPage.vue";
import MissionModulePage from "../mission-and-spacecraft/features/module-pages/MissionModulePage.vue";
import { missionSnapshots } from "../mission-and-spacecraft/features/module-pages/mission-pages.test-support";
import { groundStationFormPayload } from "../../../../modules/communications/src/features/ground-stations/fixtures.test-support";
import {
  providerNewSurface,
  providerDetailSurface,
} from "../../../../modules/communications/src/features/providers/surface-fixtures.test-support";
import { accountDetailFixture } from "../../../../modules/communications/src/features/provider-accounts/detail.test-support";
import SpacecraftPage from "../mission-and-spacecraft/SpacecraftPage.vue";
import ActivationApprovalsPage from "../capability-management/features/activation-approvals/ActivationApprovalsPage.vue";
import { inboxFixture } from "../capability-management/features/activation-approvals/fixtures.test-support";
import { identityFixture } from "../mission-and-spacecraft/features/spacecraft-identity/fixtures.test-support";
import { profileFixture } from "../mission-and-spacecraft/features/profile-creation/fixtures.test-support";

import { spacecraftDirectoryFixture } from "../mission-and-spacecraft/features/spacecraft-directory/fixtures.test-support";
import { directoryFixture } from "../mission-and-spacecraft/features/mission-directory/fixtures.test-support";
import { creationFixture } from "../mission-and-spacecraft/features/mission-creation/fixtures.test-support";
import { overviewFixture } from "../mission-and-spacecraft/features/mission-overview/fixtures.test-support";
import { installationSnapshot } from "../capability-management/features/application-installations/fixtures.test-support";
import { createHostRouter, hostRoute, shellForRoute } from "./host-navigation";
import routes from "../routes.json";
import { databaseIndexFixture } from "../catalog/features/databases/fixtures.test-support";
import { artifactFixture } from "../catalog/features/artifacts/fixtures.test-support";
import { diagnosticsFixture } from "../../../../modules/dashboards-and-exploration/src/features/runtime-diagnostics/fixtures.test-support";
import { directoryFixture as dashboardDirectoryFixture } from "../../../../modules/dashboards-and-exploration/src/features/directory/fixtures.test-support";
import { diagnosticsPageFixture } from "../../../../modules/dashboards-and-exploration/src/features/execution-diagnostics/fixtures.test-support";
import { monitorFixture } from "../../../../modules/commanding/src/features/mission-commands/monitor.test-support";
import { workspaceFixture as commandWorkspaceFixture } from "../../../../modules/commanding/src/features/workspace/fixtures.test-support";
import { readMonitorQuery } from "../../../../modules/commanding/src/features/mission-commands/monitor-query";
import {
  fixture as explorationFixture,
  selectedFixture as explorationSelectedFixture,
} from "../../../../modules/dashboards-and-exploration/src/features/exploration/fixtures.test-support";
import {
  editPage,
  forContext,
  viewPage,
} from "../../../../modules/dashboards-and-exploration/src/features/dashboard/fixtures.test-support";

const dashboardContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  resourceId: "dashboard-1",
};
const dashboardEditPage = (sequence = 0, dirty = false) =>
  forContext(editPage(sequence, dirty), dashboardContext);

function snapshot(path: string, mission: string | null = null) {
  const page =
    path === "/missions"
      ? "mission_list"
      : path === "/missions/new"
        ? "mission_new"
        : mission && path === `/missions/${mission}`
          ? "mission_overview"
          : null;
  return {
    path,
    presentation: null,
    error: null,
    spacecraft_page:
      path.split("?")[0] === `/missions/${mission}/spacecraft`
        ? {
            page: "spacecraft_list",
            version: 1,
            status: "ready",
            data: spacecraftDirectoryFixture(),
          }
        : null,
    mission_page: page && {
      page,
      version: 1,
      status: "ready",
      data:
        page === "mission_list"
          ? directoryFixture()
          : page === "mission_new"
            ? creationFixture()
            : overviewFixture(required(mission)),
    },
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
function creationSnapshot(token: string) {
  const page = snapshot("/missions/new");
  return { ...page, mission_page: { ...required(page.mission_page), creation_token: token } };
}
function requestedPath(index: number): string {
  const path = required(transport.requests[index]).payload.path;
  if (typeof path !== "string") throw new Error("Expected a host request path");
  return path;
}
function diagnosticsSnapshot(path: string) {
  const data = diagnosticsFixture();
  for (const [key, value] of new URL(path, "https://cadence.test").searchParams)
    if (
      key === "dashboard_id" ||
      key === "mission_id" ||
      key === "boundary" ||
      key === "context_reason" ||
      key === "replay_run_id" ||
      key === "affected_placement_id"
    )
      data.filters.values[key] = value;
  return {
    ...snapshot(path),
    diagnostics: [
      {
        id: "dashboards.runtime-diagnostics",
        version: 1,
        status: "ready",
        data,
      },
    ],
  };
}
let wrapper: VueWrapper | undefined;
const view = () => required(wrapper);
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
test("Explore opens its admitted origin through host navigation and restores the investigation with history", async () => {
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
  const rail = view().get("#ops-nav-rail").element;
  const origin = "/missions/mission-1/ops/dashboards/origin";
  await view().get("#exploration-open-origin").trigger("click");
  await flushHostUpdates();
  expect(transport.requests[1]).toMatchObject({ event: "host:context", payload: { path: origin } });
  await reply(1, {
    ...snapshot(origin, "mission-1"),
    ops_page: {
      id: "dashboards.workspace",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1", resourceId: "origin" },
      data: forContext(viewPage(), { ...dashboardContext, resourceId: "origin" }),
    },
  });
  expect(view().get('[data-workspace-value="battery"]').text()).toBe("28.40");
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(2)).toBe(path);
  await reply(2, state);
  expect(view().get("#exploration-open-origin").attributes("href")).toBe(origin);
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(transport.requests.every((request) => request.event === "host:context")).toBe(true);
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
test("compiled diagnostics selects through host URLs, restores history and keeps its Ops rails", async () => {
  await start();
  const base = "/missions/mission-1/ops/dashboards/dashboard-1/diagnostics";
  const data = diagnosticsPageFixture();
  Object.assign(data.model, {
    organization_id: "org-1",
    mission_id: "mission-1",
    dashboard_id: "dashboard-1",
  });
  const stateAt = (path: string, selection = data.selection) => ({
    ...snapshot(path, "mission-1"),
    ops_page: {
      id: "dashboards.execution-diagnostics",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1", resourceId: "dashboard-1" },
      data: { ...data, selection },
    },
  });
  await click(base);
  await reply(0, stateAt(base));
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  const rail = view().get("#ops-nav-rail").element;
  await view()
    .get(`#diagnostics-row-${"a".repeat(64)}`)
    .trigger("click");
  await flushHostUpdates();
  const selectedPath = requestedPath(1);
  const selection = { ...data.selection, row: "a".repeat(64) };
  expect(new URL(selectedPath, "http://cadence.test").searchParams.get("row")).toBe(selection.row);
  await reply(1, stateAt(selectedPath, selection));
  expect(
    view().get<HTMLInputElement | HTMLSelectElement>("#diagnostic-identity").element.value,
  ).toBe("dashboard");
  await view().get("#diagnostics-collection-frames").trigger("click");
  await flushHostUpdates();
  const framesPath = requestedPath(2);
  await reply(2, stateAt(framesPath, { collection: "frames", row: null, filter: "" }));
  expect(view().get("#diagnostics-collection-frames").attributes("aria-current")).toBe("true");
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(3)).toBe(selectedPath);
  await reply(3, stateAt(selectedPath, selection));
  expect(
    view().get<HTMLInputElement | HTMLSelectElement>("#diagnostic-identity").element.value,
  ).toBe("dashboard");
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(view().get("#diagnostics-loaded-at").attributes("datetime")).toBe(data.model.loaded_at);
});
test("the dashboard editor guards host navigation and back while it holds unsaved changes", async () => {
  const confirm = vi.fn(() => false);
  vi.stubGlobal("confirm", confirm);
  try {
    await start();
    const path = "/missions/mission-1/ops/dashboards/dashboard-1/edit";
    await click(path);
    await reply(0, {
      ...snapshot(path, "mission-1"),
      ops_page: dashboardEnvelope(
        dashboardEditPage(1, true),
        "11111111-1111-4111-8111-111111111111",
      ),
    });
    expect(view().find("#host-route-unavailable").exists()).toBe(false);
    const rail = view().get("#ops-nav-rail").element;
    await click("/missions/mission-1/ops/dashboards");
    expect(confirm).toHaveBeenCalledOnce();
    expect(transport.requests).toHaveLength(1);
    hostBrowserHistory.go(-1);
    await flushHostUpdates();
    expect(confirm).toHaveBeenCalledTimes(2);
    expect(transport.requests).toHaveLength(1);
    confirm.mockReturnValue(true);
    await click("/missions/mission-1/ops/dashboards");
    await reply(1, {
      ...snapshot("/missions/mission-1/ops/dashboards", "mission-1"),
      ops_page: {
        id: "dashboards.directory",
        slot: "ops.page",
        version: 1,
        status: "ready",
        token: "22222222-2222-4222-8222-222222222222",
        context: { organizationId: "org-1", missionId: "mission-1" },
        data: dashboardDirectoryFixture(),
      },
    });
    expect(view().get("#ops-nav-rail").element).toBe(rail);
    expect(view().find("#dashboard-directory-feature").exists()).toBe(true);
  } finally {
    vi.unstubAllGlobals();
  }
});
test("the dashboard editor stages a section, saves in place, then exits to the live viewer", async () => {
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  try {
    await start();
    const path = "/missions/mission-1/ops/dashboards/dashboard-1/edit";
    const token = "11111111-1111-4111-8111-111111111111";
    await click(path);
    await reply(0, {
      ...snapshot(path, "mission-1"),
      ops_page: dashboardEnvelope(dashboardEditPage(), token),
    });
    await view().get('[aria-label="Dashboard editing"] button:nth-child(2)').trigger("click");
    await flushHostUpdates();
    await view().get("#section-title").setValue("Thermal");
    await view().get(".cadence-sheet form").trigger("submit");
    expect(transport.requests[1]).toMatchObject({
      event: "host:ops-page",
      payload: {
        path,
        event: "add_section",
        input: {
          sequence: 1,
          command: { title: "Thermal", expected_version: 2, expected_revision: 0 },
        },
      },
    });
    await reply(1, {
      status: "ok",
      code: null,
      page: dashboardEnvelope(dashboardEditPage(1, true), token),
    });
    await flushHostUpdates();
    expect(view().find(".cadence-sheet").exists()).toBe(false);
    await click("/missions/mission-1/ops/dashboards");
    expect(transport.requests).toHaveLength(2);
    // Like Grafana: Save dashboard opens the save drawer and keeps the author editing.
    const button = (text: string) =>
      view()
        .findAll("button")
        .find((b) => b.text() === text);
    await button("Save dashboard")?.trigger("click");
    await flushHostUpdates();
    expect(view().get(".cadence-sheet").text()).toContain("Changes (1)");
    await view().get(".cadence-sheet form").trigger("submit");
    expect(transport.requests[2]).toMatchObject({
      event: "host:ops-page",
      payload: {
        event: "save",
        input: { sequence: 2, command: { expected_version: 2, expected_revision: 1 } },
      },
    });
    await reply(2, {
      status: "ok",
      code: null,
      result: null,
      page: dashboardEnvelope(dashboardEditPage(2, false), token),
    });
    await flushHostUpdates();
    expect(transport.requests).toHaveLength(3);
    expect(view().find(".cadence-sheet").exists()).toBe(false);
    // Nothing unsaved remains, so Exit edit returns to the viewer without asking.
    await button("Exit edit")?.trigger("click");
    await flushHostUpdates();
    expect(transport.requests[3]).toMatchObject({
      event: "host:context",
      payload: { path: "/missions/mission-1/ops/dashboards/dashboard-1" },
    });
  } finally {
    vi.unstubAllGlobals();
  }
});

function dashboardEnvelope(data: unknown, token: string) {
  return {
    id: "dashboards.workspace",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context: dashboardContext,
    data,
  };
}

function setupSnapshot() {
  const base = snapshot("/missions/mission-1/comms/ground-stations/new", "mission-1");
  const state = {
    ...base,
    mission_module_page: {
      id: "comms.ground-station-new",
      slot: "mission.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data: {
        phase: "editing",
        model: {
          navigation: { fallback_href: base.path, breadcrumbs: [] },
          data: groundStationFormPayload("new"),
        },
      },
    },
  };
  return state;
}
test("dashboard directory uses the Ops port and keeps the workspace through an unconfirmed effect", async () => {
  const state = {
    ...snapshot("/missions/mission-1/ops/dashboards", "mission-1"),
    ops_page: {
      id: "dashboards.directory",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data: dashboardDirectoryFixture(),
    },
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  const rail = view().get("#ops-nav-rail").element;
  await view().get("[aria-label='Star Power Bus']").trigger("click");
  expect(transport.requests[0]).toEqual(
    containing({
      event: "host:ops-page",
      payload: {
        id: state.ops_page.id,
        token: state.ops_page.token,
        path: state.path,
        event: "star",
        input: { sequence: 1, command: { dashboard_id: "dashboard-2", starred: true } },
      },
    }),
  );
  await reply(0, { status: "unknown" });
  expect(view().get("#dashboard-directory-notice").text()).toContain("could not be confirmed");
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(view().get("#dashboard-dashboard-2").attributes("data-starred")).toBe("false");
  expect(transport.requests).toHaveLength(1);
});
test("the dashboard viewer binds the path resource and keeps the Ops frame through live refresh and failure", async () => {
  const path = "/missions/mission-1/ops/dashboards/dashboard-1";
  const base = snapshot(path, "mission-1");
  const model = forContext(viewPage(), dashboardContext);
  const state = {
    ...base,
    ops_page: dashboardEnvelope(model, "11111111-1111-4111-8111-111111111111"),
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  expect(view().get('[data-workspace-value="battery"]').text()).toBe("28.40");
  // The dashboard owns its identity bar; the host heading is omitted, not hidden.
  expect(view().find("#host-page-heading").exists()).toBe(false);
  expect(
    view()
      .findAll("h1")
      .map((h) => h.text()),
  ).toEqual(["Flight telemetry"]);
  const rail = view().get("#ops-nav-rail").element,
    grid = view().get(".grid-stack").element;
  // A live refresh is a props update from Phoenix: same page instance, same grid.
  await wrapper.setProps({
    snapshot: { ...state, ops_page: { ...state.ops_page, data: structuredClone(model) } },
  });
  await flushHostUpdates();
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(view().get(".grid-stack").element).toBe(grid);
  await view().get("#dashboard-time-range .cadence-dashboard-query-trigger").trigger("click");
  await flushHostUpdates();
  const lastHour = view()
    .findAll("button")
    .find((b) => b.text() === "Last 1 hour");
  await lastHour?.trigger("click");
  await flushHostUpdates();
  expect(requestedPath(0)).toContain("from=now-1h");
  expect(requestedPath(0)).toContain("to=now");
  await reply(0, {
    ...state,
    path: requestedPath(0),
    ops_page: { ...state.ops_page, context: { ...state.ops_page.context, resourceId: "foreign" } },
  });
  expect(view().find("#ops-module-unavailable").exists()).toBe(true);
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
});
test("dashboard creation uses the token-bound Ops port and retains its lock on host refresh", async () => {
  const state = {
    ...snapshot("/missions/mission-1/ops/dashboards/new?mode=import", "mission-1"),
    ops_page: {
      id: "dashboards.creation",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data: {
        sequence: 0,
        phase: "editing",
        model: { version: 1, mission_id: "mission-1", mode: "import", source: null },
      },
    },
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  const rail = view().get("#ops-nav-rail").element;
  const name = view().get<HTMLInputElement>("#dashboard-name").element;
  await view().get("#dashboard-name").setValue("Imported");
  await view().get("#dashboard-document-json").setValue("{}");
  await view().get("#dashboard-new-form").trigger("submit");
  expect(required(transport.requests[0]).payload).toEqual({
    id: "dashboards.creation",
    token: state.ops_page.token,
    path: state.path,
    event: "create",
    input: {
      sequence: 1,
      source_version: null,
      dashboard: { name: "Imported", description: "", document_json: "{}" },
    },
  });
  await reply(0, { status: "unknown", sequence: 1 });
  await view().get("#dashboard-creation-refresh").trigger("click");
  await reply(1, {
    ...state,
    ops_page: {
      ...state.ops_page,
      data: { ...state.ops_page.data, sequence: 1, phase: "submitted" },
    },
  });
  expect(view().get("#ops-nav-rail").element).toBe(rail);
  expect(view().get("#dashboard-name").element).toBe(name);
  expect(name.value).toBe("Imported");
  expect(view().get("#dashboard-new-submit").attributes("disabled")).toBeDefined();
  expect(transport.requests).toHaveLength(2);
});

test("provider creation and detail share the mission host port without loading a remote", async () => {
  const state = {
    ...snapshot("/missions/mission-1/comms/providers/new", "mission-1"),
    mission_module_page: {
      id: "comms.provider-new",
      slot: "mission.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: { organizationId: "org-1", missionId: "mission-1" },
      data: { model: providerNewSurface(), phase: "editing", sequence: 0 },
    },
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#mission-provider-form").trigger("submit");
  expect(transport.requests[0]).toEqual(
    containing({
      event: "host:mission-page",
      payload: containing({
        id: "comms.provider-new",
        token: state.mission_module_page.token,
        path: state.path,
        event: "create-provider",
        input: containing({ sequence: 1 }),
      }),
    }),
  );
  await reply(0, {
    status: "ok",
    sequence: 1,
    data: { result: { provider_id: "provider-1", version: 1, display_name: "Created" } },
  });
  const detail = {
    ...snapshot("/missions/mission-1/comms/providers/provider-1", "mission-1"),
    mission_module_page: {
      ...state.mission_module_page,
      id: "comms.provider-show",
      token: "22222222-2222-4222-8222-222222222222",
      context: { ...state.mission_module_page.context, resourceId: "provider-1" },
      data: { model: providerDetailSurface(), phase: "editing", sequence: 0 },
    },
  };
  expect(requestedPath(1)).toBe(detail.path);
  await reply(1, detail);
  await view().get("#host-action-validate-provider-button").trigger("click");
  expect(required(transport.requests[2]).payload).toEqual({
    id: "comms.provider-show",
    token: detail.mission_module_page.token,
    path: detail.path,
    event: "validate-provider",
    input: { provider_id: "provider-1", expected_provider_version: 1, sequence: 1 },
  });
  await reply(2, { status: "unknown", sequence: 1 });
  expect(view().get("#host-action-sync-provider-button").attributes("disabled")).toBeDefined();
});
test("mission setup uses page-bound host actions and only confirmed saves navigate", async () => {
  const state = setupSnapshot();
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#ground_station_display_name").setValue("Host station");
  expect(transport.requests[0]).toEqual(
    containing({
      event: "host:mission-page",
      payload: containing({
        id: state.mission_module_page.id,
        token: state.mission_module_page.token,
        path: state.path,
        event: "validate",
      }),
    }),
  );
  await reply(0, { status: "ok", data: { result: { valid: true } } });
  await view().get("#ground-station-form").trigger("submit");
  expect(required(transport.requests[1]).payload.event).toBe("save");
  await reply(1, {
    status: "ok",
    data: {
      result: { navigation: { href: "/missions/mission-1/comms/ground-stations/station-1" } },
    },
  });
  expect(transport.requests[2]).toEqual(
    containing({
      event: "host:context",
      payload: { path: "/missions/mission-1/comms/ground-stations/station-1" },
    }),
  );
  await reply(2, snapshot("/missions/mission-1/comms/ground-stations/station-1", "mission-1"));
});
test("pending navigation rejects old mission actions and late save replies cannot navigate", async () => {
  const state = setupSnapshot();
  wrapper = mount(BrowserHost, { attachTo: document.body, props: { snapshot: state } });
  await flushHostUpdates();
  const hostAction = required(view().getComponent(MissionModulePage).props("execute"));
  const payload = {
    id: state.mission_module_page.id,
    token: state.mission_module_page.token,
    event: "validate",
    input: {},
  };
  await expect(hostAction({ ...payload, token: "foreign" })).rejects.toThrow();
  await view().get("#ground_station_display_name").setValue("Late station");
  await reply(0, { status: "ok", data: { result: { valid: true } } });
  await view().get("#ground-station-form").trigger("submit");
  await click("/missions");
  await expect(hostAction(payload)).rejects.toThrow();
  await reply(2, snapshot("/missions"));
  await reply(1, {
    status: "ok",
    data: {
      result: { navigation: { href: "/missions/mission-1/comms/ground-stations/station-1" } },
    },
  });
  expect(transport.requests).toHaveLength(3);
  expect(view().getComponent(MissionPage).props("page")).toBe("mission_list");
});
test("organization directory composes Communications and recovers without a federated surface", async () => {
  const base = snapshot("/provider-accounts");
  const contribution = {
    id: "comms.provider-account-directory",
    slot: "organization.page",
    version: 1,
    context: { organizationId: "org-1" },
    status: "ready",
    data: listFixture(),
  };
  const state = { ...base, organization_module_page: { ...contribution, status: "unavailable" } };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#organization-module-unavailable").exists()).toBe(true);
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#organization-module-retry").trigger("click");
  expect(required(transport.requests[0]).payload).toEqual({ path: "/provider-accounts" });
  await reply(0, { ...state, organization_module_page: contribution });
  expect(view().find("#provider-account-account-1").exists()).toBe(true);
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
});
test("registration uses page-bound host actions and navigates only after a confirmed feature receipt", async () => {
  const base = snapshot("/provider-accounts/new");
  const token = "11111111-1111-4111-8111-111111111111";
  const state = {
    ...base,
    organization_module_page: {
      id: "comms.provider-account-registration",
      slot: "organization.page",
      version: 1,
      context: { organizationId: "org-1" },
      status: "ready",
      token,
      data: registrationModel(),
    },
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#account-display_name").setValue("Host draft");
  const validation = required(transport.requests[0]);
  expect(validation.event).toBe("host:organization-page");
  expect(validation.payload).toEqual(
    containing({
      id: state.organization_module_page.id,
      token,
      path: state.path,
      event: "validate",
    }),
  );
  expect(required(transport.requests[0]).payload.input).toEqual({
    provider_account: {
      ...registrationValues(state.organization_module_page.data.form),
      display_name: "Host draft",
    },
  });
  await reply(0, {
    status: "ok",
    data: validationReceipt({
      ...registrationValues(state.organization_module_page.data.form),
      display_name: "Host draft",
    }),
  });
  await view().get("#registration-form").trigger("submit");
  expect(required(transport.requests[1]).payload.event).toBe("save");
  await reply(1, { status: "ok", data: receipt({ navigate: "/provider-accounts/account-1" }) });
  expect(transport.requests[2]).toEqual(
    containing({
      event: "host:context",
      payload: { path: "/provider-accounts/account-1" },
    }),
  );
  await reply(2, snapshot("/provider-accounts/account-1"));
});
test("account detail binds refresh and effect sequence to its route and contains a foreign account DTO", async () => {
  const base = snapshot("/provider-accounts/account-1"),
    model = accountDetailFixture();
  const token = "11111111-1111-4111-8111-111111111111";
  const state = {
    ...base,
    organization_module_page: {
      id: "comms.provider-account-detail",
      slot: "organization.page",
      version: 1,
      status: "ready",
      token,
      context: { organizationId: "org-1", resourceId: "account-1" },
      data: { model, sequence: 4, locked: false },
    },
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#grant-grant_reason").setValue("Preserved");
  await view().get("#refresh-provider-account").trigger("click");
  expect(transport.requests[0]).toEqual(
    containing({
      event: "host:organization-page",
      payload: {
        id: state.organization_module_page.id,
        token,
        path: state.path,
        event: "refresh",
        input: {},
      },
    }),
  );
  await reply(0, { status: "ok", data: model });
  expect(view().get("#grant-grant_reason").element).toHaveProperty("value", "Preserved");
  await view().get("#host-action-validate-account").trigger("click");
  expect(required(transport.requests[1]).payload.input).toEqual(
    containing({
      provider_account_id: "account-1",
      expected_credential_version: 2,
      sequence: 5,
    }),
  );
  await reply(1, { status: "ok", data: receipt({ patch: model }) });
  await view().setProps({
    snapshot: {
      ...state,
      organization_module_page: {
        ...state.organization_module_page,
        context: { organizationId: "org-1", resourceId: "foreign" },
      },
    },
  });
  await flushHostUpdates();
  expect(view().find("#organization-module-unavailable").exists()).toBe(true);
});
test("spacecraft routing composes Communications without mounting a federated surface", async () => {
  const base = snapshot("/missions/mission-1/spacecraft/spacecraft-1/routing", "mission-1");
  const state = {
    ...base,
    context: {
      ...base.context,
      spacecraft: { spacecraft_id: "spacecraft-1", display_name: "Nova-1" },
    },
    spacecraft_module_page: spacecraftRoutingSnapshot(),
  };
  wrapper = mount(BrowserHost, {
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#spacecraft-routing-rule-rule-1").exists()).toBe(true);
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  expect(transport.pushEvent).not.toHaveBeenCalled();
});
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

test("activation decisions bind path and token and cannot replace a later visit to the same inbox", async () => {
  await start();
  const path = "/missions/mission-1/ops/activations";
  const original = { ...snapshot(path, "mission-1"), activation_approvals: inboxFixture() };
  await click(path);
  await reply(0, original);
  const input = {
    activation_decision: { request_id: "request-1", reason: "Reviewed" },
    decision: "rejected" as const,
  };
  const execute: (value: typeof input) => Promise<unknown> = view()
    .getComponent(ActivationApprovalsPage)
    .props("execute");
  const pending = execute(input);
  expect(required(transport.requests[1]).event).toBe("host:activation");
  expect(required(transport.requests[1]).payload).toEqual({ path, token: "review-token", input });
  await click("/missions");
  await reply(2, snapshot("/missions"));
  await click(path);
  const successor = {
    ...original,
    activation_approvals: { ...inboxFixture(), token: "new-visit-token" },
  };
  await reply(3, successor);
  await reply(1, {
    result: {
      status: "ok",
      data: { activationRequestId: "request-1", decision: "rejected", outcome: "rejected" },
    },
    page: original,
  });
  await pending;
  expect(view().getComponent(ActivationApprovalsPage).props("snapshot")).toMatchObject({
    token: "new-visit-token",
  });
});

test("host remounts within the same Vue app and ignores the previous instance's pending reply", async () => {
  const listen = vi.spyOn(hostBrowserHistory, "listen");
  const destroyHistory = vi.spyOn(hostBrowserHistory, "destroy");
  try {
    wrapper = mount(
      defineComponent({
        data: () => ({ revision: 0 }),
        render() {
          return h(BrowserHost, { key: this.revision, snapshot: snapshot("/missions") });
        },
      }),
      { attachTo: document.body },
    );
    await flushHostUpdates();
    expect(view().find("#mission-list-table").exists()).toBe(true);
    await click("/missions/old-mission");
    expect(transport.requests).toHaveLength(1);
    await view().setData({ revision: 1 });
    await flushHostUpdates();
    expect(view().find("#mission-list-table").exists()).toBe(true);
    await reply(0, snapshot("/missions/old-mission", "old-mission"));
    expect(view().find("#mission-list-table").exists()).toBe(true);
    await click("/missions/current-mission");
    expect(transport.requests).toHaveLength(2);
    await reply(1, snapshot("/missions/current-mission", "current-mission"));
    expect(view().getComponent(MissionPage).props("page")).toBe("mission_overview");
    hostBrowserHistory.go(-1);
    await flushHostUpdates();
    expect(transport.requests).toHaveLength(3);
    await reply(2, snapshot("/missions"));
    expect(view().find("#mission-list-table").exists()).toBe(true);
    expect(listen).toHaveBeenCalledTimes(2);
    expect(destroyHistory).not.toHaveBeenCalled();
  } finally {
    listen.mockRestore();
    destroyHistory.mockRestore();
  }
});

test("mission creation sends its page token and stale completion cannot redirect later navigation", async () => {
  const app = await start();
  await click("/missions/new");
  const creation = creationSnapshot("creation-one");
  await reply(0, creation);
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  await app.get("#mission_display_name").setValue("Flight");
  await reply(1, { status: "ok", errors: {} });
  await app.get("#mission_slug").setValue("flight");
  await reply(2, { status: "ok", errors: {} });
  await app.get("#mission-form").trigger("submit");
  expect(transport.requests[3]).toMatchObject({
    event: "host:mission",
    payload: {
      path: "/missions/new",
      token: "creation-one",
      event: "save",
      input: { mission: { display_name: "Flight", slug: "flight" } },
    },
  });
  await click("/missions");
  await reply(4, snapshot("/missions"));
  await reply(3, { status: "ok", errors: {}, data: { mission: { href: "/missions/created" } } });
  expect(transport.requests).toHaveLength(5);
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_list");
});

test("installation actions are path-bound and an old reply cannot replace a revisited inventory", async () => {
  const app = await start();
  const path = "/missions/mission-a/applications";
  const inventory = () => ({
    ...snapshot(path, "mission-a"),
    application_management: installationSnapshot(),
  });
  await click(path);
  await reply(0, inventory());
  expect(app.find("#mission-applications-list").exists()).toBe(true);
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  await app.get("#limits-install").trigger("click");
  expect(transport.requests[1]).toMatchObject({
    event: "host:manage",
    payload: { path, event: "install", key: "limits" },
  });
  await app.get("#limits-install").trigger("click");
  expect(transport.requests).toHaveLength(2);
  await click("/missions");
  await reply(2, snapshot("/missions"));
  await click(path);
  const fresh = inventory();
  if (!("applications_component" in fresh.application_management.data))
    throw new Error("Expected mission installation data");
  required(
    fresh.application_management.data.applications_component.props.applications[0],
  ).display_name = "Latest inventory";
  await reply(3, fresh);
  await reply(1, inventory());
  expect(app.get("#mission-applications-list").text()).toContain("Latest inventory");
  expect(transport.requests).toHaveLength(4);
});

test("a failed installation action stays contained in the feature and releases its controls", async () => {
  const app = await start();
  const path = "/missions/mission-a/applications";
  await click(path);
  await reply(0, {
    ...snapshot(path, "mission-a"),
    application_management: installationSnapshot(),
  });
  const sidebar = app.get("[data-sidebar-collapsible]").element;
  await app.get("#limits-install").trigger("click");
  required(required(transport.requests[1]).reply)({ ok: false });
  await flushHostUpdates();
  expect(app.find("#application-installation-action-error").exists()).toBe(true);
  expect(app.get("#limits-install").attributes("disabled")).toBeUndefined();
  expect(app.get("[data-sidebar-collapsible]").element).toBe(sidebar);
});

test("successful mission creation navigates through the host authorization guard", async () => {
  const app = await start();
  await click("/missions/new");
  const creation = creationSnapshot("creation-one");
  await reply(0, creation);
  await app.get("#mission-form").trigger("submit");
  await reply(1, { status: "ok", errors: {}, data: { mission: { href: "/missions/created" } } });
  expect(transport.requests[2]).toMatchObject({
    event: "host:context",
    payload: { path: "/missions/created" },
  });
  await reply(2, snapshot("/missions/created", "created"));
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_overview");
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
});

test("spacecraft creation sends an explicit profile version and token, then returns through host authorization", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft/new";
  await click(path);
  await reply(0, {
    ...snapshot(path, "mission-a"),
    spacecraft_page: {
      page: "spacecraft_new",
      version: 1,
      status: "ready",
      form_token: "spacecraft-token",
      data: identityFixture(),
    },
  });
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  await app.get("#spacecraft-display-name").setValue("Vehicle");
  await reply(1, { status: "ok", errors: {} });
  await app.get("#spacecraft-spacecraft-type-id").setValue(JSON.stringify(["profile-one", 1]));
  await reply(2, { status: "ok", errors: {} });
  await app.get("#spacecraft-form").trigger("submit");
  expect(transport.requests[3]).toMatchObject({
    event: "host:spacecraft",
    payload: {
      path,
      token: "spacecraft-token",
      event: "save",
      input: { spacecraft: { spacecraft_type_id: "profile-one", spacecraft_type_version: 1 } },
    },
  });
  await reply(3, { status: "ok", errors: {}, data: { href: "/missions/mission-a/spacecraft" } });
  expect(transport.requests[4]).toMatchObject({
    event: "host:context",
    payload: { path: "/missions/mission-a/spacecraft" },
  });
  await reply(4, snapshot("/missions/mission-a/spacecraft", "mission-a"));
  expect(app.find("#spacecraft-list-content").exists()).toBe(true);
});

test("a stale spacecraft save cannot redirect after leaving and revisiting the creation page", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft/new";
  const creation = (token: string) => ({
    ...snapshot(path, "mission-a"),
    spacecraft_page: {
      page: "spacecraft_new",
      version: 1,
      status: "ready",
      form_token: token,
      data: identityFixture(),
    },
  });
  await click(path);
  await reply(0, creation("old"));
  await app.get("#spacecraft-form").trigger("submit");
  await click("/missions");
  await reply(2, snapshot("/missions"));
  await click(path);
  await reply(3, creation("new"));
  await reply(1, { status: "ok", errors: {}, data: { href: "/missions/mission-a/spacecraft" } });
  expect(transport.requests).toHaveLength(4);
  expect(app.find("#spacecraft-form").exists()).toBe(true);
});

test("mission entry commits page and sidebar together after authorized context arrives", async () => {
  const app = await start();
  const sidebar = app.get("[data-sidebar-collapsible]").element;
  await click("/missions/mission-a");
  expect(required(transport.requests[0]).payload).toEqual({ path: "/missions/mission-a" });
  expect(app.find('a[href="/missions/mission-a/spacecraft"]').exists()).toBe(false);
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  expect(app.get("[data-sidebar-collapsible]").element).toBe(sidebar);
  expect(app.get('a[href="/missions/mission-a"]').attributes("aria-current")).toBe("page");
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_overview");
  expect(app.find("#spacecraft-readiness-sc-one").exists()).toBe(true);
});

test("core Catalog navigation renders real pages without a federation surface", async () => {
  const app = await start();
  const path = "/missions/mission-a/catalog";
  await click(path);
  await reply(0, {
    ...snapshot(path, "mission-a"),
    catalog: { page: "catalog_index", version: 1, status: "ready", data: databaseIndexFixture() },
  });
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  expect(app.find("#database-row-one").exists()).toBe(true);
  expect(app.findAll("h1")).toHaveLength(1);
  const artifactPath = `${path}/artifacts/one`;
  await click(artifactPath);
  await reply(1, {
    ...snapshot(artifactPath, "mission-a"),
    catalog: {
      page: "catalog_artifact_show",
      version: 1,
      status: "ready",
      data: artifactFixture(),
    },
  });
  await app.get("#catalog-artifact-reimport-button").trigger("click");
  expect(transport.requests[2]).toMatchObject({
    event: "host:catalog",
    payload: { event: "reimport", path: artifactPath },
  });
  // Completing an old action must not redirect a newly visited page.
  await click("/missions");
  await reply(3, snapshot("/missions"));
  await reply(2, { href: `${path}/imports/new-run` });
  expect(transport.requests).toHaveLength(4);
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_list");
});

test("spacecraft query navigation preserves the search node and late replies cannot replace a newer query", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft";
  await click(path);
  await reply(0, snapshot(path, "mission-a"));
  const search = app.get<HTMLInputElement>("#spacecraft-roster-toolbar-search");
  search.element.focus();
  const shell = required(nativeElement(app.element));
  await app.get("#spacecraft-sort-name").trigger("click");
  await flushHostUpdates();
  const sortedPath = requestedPath(1);
  const sorted = snapshot(sortedPath, "mission-a");
  required(sorted.spacecraft_page).data.presentation.roster.sort_by = "display_name";
  await reply(1, sorted);
  expect(app.get("#spacecraft-roster-toolbar-search").element).toBe(search.element);
  expect(document.activeElement).toBe(search.element);
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  await app.get("#spacecraft-next-page").trigger("click");
  await flushHostUpdates();
  const oldPath = requestedPath(2);
  await app.get("#spacecraft-tile-missing-scid").trigger("click");
  await flushHostUpdates();
  const filteredPath = requestedPath(3);
  const filtered = snapshot(filteredPath, "mission-a");
  required(filtered.spacecraft_page).data.presentation.roster.search = "Latest query";
  await reply(3, filtered);
  await reply(2, snapshot(oldPath, "mission-a"));
  expect(
    app.get<HTMLInputElement | HTMLSelectElement>("#spacecraft-roster-toolbar-search").element
      .value,
  ).toBe("Latest query");
  expect(app.element).toBe(shell);
});

test("malformed core spacecraft data preserves navigation and a retry recovers the page", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft";
  await click(path);
  const invalid = snapshot(path, "mission-a");
  // @ts-expect-error Deliberately malformed producer data must render the contained error.
  required(invalid.spacecraft_page).data = {};
  await reply(0, invalid);
  const sidebar = app.get("[data-sidebar-collapsible]").element;
  expect(app.find("#core-spacecraft-error").exists()).toBe(true);
  await app.get("#core-spacecraft-retry").trigger("click");
  await reply(1, snapshot(path, "mission-a"));
  expect(app.get("[data-sidebar-collapsible]").element).toBe(sidebar);
  expect(app.find("#spacecraft-list-content").exists()).toBe(true);
});

test("a scheduled spacecraft search cannot redirect back while another page is authorizing", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft";
  await click(path);
  await reply(0, snapshot(path, "mission-a"));
  vi.useFakeTimers();
  try {
    await app.get("#spacecraft-roster-toolbar-search").setValue("delayed");
    await click("/missions");
    await vi.advanceTimersByTimeAsync(350);
    expect(transport.requests).toHaveLength(2);
    expect(requestedPath(1)).toBe("/missions");
    await reply(1, snapshot("/missions"));
    expect(app.getComponent(MissionPage).props("page")).toBe("mission_list");
  } finally {
    vi.useRealTimers();
  }
});

test("administration diagnostics is host-owned and filters/refresh use authorized host navigation", async () => {
  const app = await start();
  await click("/admin/runtime");
  await reply(0, diagnosticsSnapshot("/admin/runtime"));
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  expect(app.find("#administration-diagnostics-page").exists()).toBe(true);
  expect(app.find("#admin-runtime-decisions-empty").exists()).toBe(true);
  expect(app.findAll("h1")).toHaveLength(1);
  await app.get("#admin-runtime-refresh").trigger("click");
  expect(required(transport.requests[1]).payload).toEqual({ path: "/admin/runtime" });
  await reply(1, diagnosticsSnapshot("/admin/runtime"));
  const filter = app.get<HTMLInputElement>("#runtime_decision_filters_dashboard_id");
  filter.element.focus();
  await filter.setValue("dashboard-a");
  await flushHostUpdates();
  expect(new URL(requestedPath(2), "https://cadence.test").searchParams.get("dashboard_id")).toBe(
    "dashboard-a",
  );
  await reply(2, diagnosticsSnapshot(requestedPath(2)));
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  expect(app.get("#runtime_decision_filters_dashboard_id").element).toBe(filter.element);
  expect(document.activeElement).toBe(filter.element);
  expect(filter.element.value).toBe("dashboard-a");
});

test("a late diagnostics refresh cannot replace a newer navigation or report its stale failure", async () => {
  const app = await start();
  await click("/admin/runtime");
  await reply(0, diagnosticsSnapshot("/admin/runtime"));
  await app.get("#admin-runtime-refresh").trigger("click");
  await click("/missions");
  await reply(2, snapshot("/missions"));
  required(required(transport.requests[1]).reply)({ ok: false });
  await flushHostUpdates();
  expect(app.find("#administration-diagnostics-page").exists()).toBe(false);
  expect(app.find("#host-navigation-error").exists()).toBe(false);
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_list");
});

test("late navigation and live-prop responses cannot replace the committed mission", async () => {
  const app = await start();
  await click("/missions/mission-a");
  await click("/missions/mission-b");
  await reply(1, snapshot("/missions/mission-b", "mission-b"));
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  await app.setProps({ snapshot: snapshot("/missions/mission-a", "mission-a") });
  expect(app.getComponent(MissionPage).props("snapshot")).toMatchObject({
    data: { overview: { mission: { slug: "mission-b" } } },
  });
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

test("mission read pages retain the host shell and bind detail identity to the path without a remote", async () => {
  const app = await start();
  const shell = required(nativeElement(app.element));
  const path = "/missions/mission-1/comms/transports";
  await click(path);
  const state = { ...snapshot(path, "mission-1"), mission_module_page: missionSnapshots()[2] };
  await reply(0, state);
  expect(app.find("#comms-transports-directory-rows").exists()).toBe(true);
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  const detail = path + "/transports-1?transport_id=forged&mission_id=forged";
  await click(detail);
  const next = { ...snapshot(detail, "mission-1"), mission_module_page: missionSnapshots()[3] };
  await reply(1, next);
  expect(app.element).toBe(shell);
  expect(app.getComponent(MissionModulePage).props("context")).toEqual({
    organizationId: "org-1",
    missionId: "mission-1",
    resourceId: "transports-1",
  });
  expect(app.find("#mission-module-unavailable").exists()).toBe(false);
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
});

test("denied context preserves the displayed page and reports a recoverable failure", async () => {
  const app = await start();
  await click("/missions/missing");
  required(required(transport.requests[0]).reply)({ ok: false });
  await flushHostUpdates();
  expect(app.getComponent(MissionPage).props("page")).toBe("mission_list");
  expect(app.get("#host-navigation-error").attributes("role")).toBe("alert");
});

test("Back and Forward reenter the guard without replacing the Vue shell", async () => {
  const app = await start();
  const shell = required(nativeElement(app.element));
  await click("/missions/mission-a/spacecraft");
  await reply(0, snapshot("/missions/mission-a/spacecraft", "mission-a"));
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  expect(requestedPath(1)).toBe("/missions");
  await reply(1, snapshot("/missions"));
  hostBrowserHistory.go(1);
  await flushHostUpdates();
  await reply(2, snapshot("/missions/mission-a/spacecraft", "mission-a"));
  expect(app.element).toBe(shell);
  expect(app.getComponent(SpacecraftPage).props("page")).toBe("spacecraft_list");
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
  await click("/missions/mission-a");
  await reply(0, snapshot("/missions/mission-a", "mission-a"));
  // A LiveView reconnect can resend its original bootstrap snapshot.
  await app.setProps({ snapshot: snapshot("/missions") });
  window.dispatchEvent(new Event("cadence:transport-reconnected"));
  await flushHostUpdates();
  expect(requestedPath(1)).toBe("/missions/mission-a");
  const refreshed = snapshot("/missions/mission-a", "mission-a");
  required(refreshed.context.mission).display_name = "Renamed Mission";
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

test("profile creation is a token-bound core action and navigates only to its profile directory", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft/profiles/new";
  await click(path);
  await reply(0, {
    ...snapshot(path, "mission-a"),
    spacecraft_page: {
      page: "profile_new",
      version: 1,
      status: "ready",
      form_token: "profile-token",
      data: profileFixture(),
    },
  });
  expect(app.find("#host-route-unavailable").exists()).toBe(false);
  await app.get("#profile-display_name").setValue("Bus");
  await reply(1, { status: "ok", errors: {} });
  await app.get("#profile-frame_size").setValue("1024");
  await reply(2, { status: "ok", errors: {} });
  await app.get("#spacecraft-profile-form").trigger("submit");
  expect(transport.requests[3]).toMatchObject({
    event: "host:spacecraft",
    payload: {
      path,
      token: "profile-token",
      event: "save",
      input: { spacecraft_type: { display_name: "Bus", frame_size: 1024 } },
    },
  });
  await reply(3, {
    status: "ok",
    errors: {},
    data: { href: "/missions/mission-a/spacecraft/profiles" },
  });
  expect(transport.requests[4]).toMatchObject({
    event: "host:context",
    payload: { path: "/missions/mission-a/spacecraft/profiles" },
  });
});

test("a late profile save cannot redirect a later mission page", async () => {
  const app = await start();
  const path = "/missions/mission-a/spacecraft/profiles/new";
  await click(path);
  await reply(0, {
    ...snapshot(path, "mission-a"),
    spacecraft_page: {
      page: "profile_new",
      version: 1,
      status: "ready",
      form_token: "old-profile-token",
      data: profileFixture(),
    },
  });
  await app.get("#spacecraft-profile-form").trigger("submit");
  await click("/missions");
  await reply(2, snapshot("/missions"));
  await reply(1, {
    status: "ok",
    errors: {},
    data: { href: "/missions/mission-a/spacecraft/profiles" },
  });
  expect(transport.requests).toHaveLength(3);
  expect(app.find("#mission-list-table").exists()).toBe(true);
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
  await click("/missions");
  await reply(4, snapshot("/missions"));
  await reply(3, fresh);
  expect(view().find("#ops-fleet-planning-page").exists()).toBe(false);
  expect(view().find("#mission-list-table").exists()).toBe(true);
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
  await click("/missions");
  await reply(3, snapshot("/missions"));
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

test("organization home composes core facts, refreshes and leaves through the persistent shell", async () => {
  const state = {
    ...snapshot("/"),
    administration_page: {
      version: 1,
      page: "organization_home",
      status: "unavailable",
      organization_id: "org-1",
    },
  };
  wrapper = mount(BrowserHost, {
    attachTo: document.body,
    props: { snapshot: state },
  });
  await flushHostUpdates();
  expect(view().find("#core-administration-error").exists()).toBe(true);
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#core-administration-retry").trigger("click");
  await reply(0, {
    ...state,
    administration_page: {
      ...state.administration_page,
      status: "ready",
      data: {
        version: 1,
        organization: { id: "org-1", name: "Operations", slug: "operations" },
        counts: { missions: 1, spacecraft: 7, active_memberships: 2 },
        recent_missions: [
          {
            id: "mission-one",
            name: "Mission One",
            slug: "one",
            created_at: "2026-09-09T12:00:00Z",
          },
        ],
      },
    },
  });
  expect(view().get("#organization-stat-spacecraft").text()).toContain("7");
  expect(view().get("#organization-recent-mission-mission-one a").attributes("href")).toBe(
    "/missions/mission-one",
  );
  await click("/missions");
  await reply(1, snapshot("/missions"));
  expect(view().find("#organization-home-page").exists()).toBe(false);
  expect(view().getComponent(MissionPage).props("page")).toBe("mission_list");
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

function notificationSnapshot(path = "/notifications", unread = true) {
  const value = {
    ...snapshot(path),
    notifications_page: {
      version: 1,
      page: "notifications",
      status: "ready",
      user_id: "u-1",
      action_token: "inbox-token",
      data: {
        version: 1,
        user_id: "u-1",
        observed_at: "2026-09-01T00:00:00Z",
        limit: 50,
        query: { unread: path.includes("unread=true") ? "true" : "", before_at: "", before_id: "" },
        next_cursor: null,
        notifications:
          !unread && path.includes("unread=true")
            ? []
            : [
                {
                  id: "notif-1",
                  kind: "organization_invitation",
                  title: "Join flight",
                  body: null,
                  created_at: "2026-08-31T00:00:00Z",
                  read_at: unread ? null : "2026-09-01T00:01:00Z",
                  invitation_status: "pending",
                },
              ],
      },
    },
  };
  value.context.unread_count = unread ? 1 : 0;
  return value;
}
test("core notifications pin actions to the current user visit and update the inbox without a remote mount", async () => {
  await start();
  await click("/notifications");
  await reply(0, notificationSnapshot());
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await view().get("#notification-mark-read-notif-1").trigger("click");
  expect(transport.requests[1]).toMatchObject({
    event: "host:notifications",
    payload: {
      path: "/notifications",
      token: "inbox-token",
      event: "mark_notification_read",
      input: { notification_id: "notif-1" },
    },
  });
  await reply(1, {
    status: "ok",
    data: { status: "read" },
    host: notificationSnapshot("/notifications", false),
  });
  expect(view().get("#notification-notif-1").attributes("data-unread")).toBe("false");
  expect(view().get("#notification-state-notif-1").text()).toBe("Invitation pending");
  await view().get("#notifications-unread").trigger("click");
  await flushHostUpdates();
  await reply(2, notificationSnapshot("/notifications?unread=true", false));
  expect(view().find("#notifications-empty-state").exists()).toBe(true);
  hostBrowserHistory.go(-1);
  await flushHostUpdates();
  await reply(3, notificationSnapshot("/notifications", false));
  expect(view().get("#notification-state-notif-1").text()).toBe("Invitation pending");
});
test("a late invitation completion cannot replace a later page or redirect the host", async () => {
  await start();
  await click("/notifications");
  await reply(0, notificationSnapshot());
  await view().get("#notification-accept-notif-1").trigger("click");
  await click("/missions");
  await reply(2, snapshot("/missions"));
  await reply(1, {
    status: "ok",
    data: { status: "accepted", navigate: "/" },
    host: notificationSnapshot("/notifications", false),
  });
  expect(transport.requests).toHaveLength(3);
  expect(view().find("#mission-list-table").exists()).toBe(true);
  expect(view().find("#notifications-page").exists()).toBe(false);
});

test("an inbox recipient change cannot admit the previous recipient action response", async () => {
  await start();
  await click("/notifications");
  await reply(0, notificationSnapshot());
  await view().get("#notification-accept-notif-1").trigger("click");
  const next = notificationSnapshot();
  next.context.user.user_id = "u-2";
  next.notifications_page.user_id = "u-2";
  next.notifications_page.action_token = "other-visit";
  next.notifications_page.data.user_id = "u-2";
  required(next.notifications_page.data.notifications[0]).id = "notif-2";
  await view().setProps({ snapshot: next });
  await flushHostUpdates();
  await reply(1, {
    status: "ok",
    data: { status: "accepted", navigate: "/" },
    host: notificationSnapshot("/notifications", false),
  });
  expect(view().find("#notification-notif-2").exists()).toBe(true);
  expect(view().find("#notification-notif-1").exists()).toBe(false);
  expect(view().find("#notification-action-message").exists()).toBe(false);
  expect(transport.requests).toHaveLength(2);
});

function platformCreationSnapshot(
  userId = "u-1",
  created: { id: string; name: string; slug: string } | null = null,
) {
  const value = snapshot("/admin/organizations/new");
  value.context.user.user_id = userId;
  return {
    ...value,
    platform_administration_page: {
      version: 1,
      page: "organization_create",
      status: "ready",
      user_id: userId,
      action_token: `visit-${userId}`,
      data: { version: 1, user_id: userId, observed_at: "2026-09-10T01:00:00Z", created },
    },
  };
}
async function submitPlatformOrganization() {
  await view().get("#organization_display_name").setValue("Flight");
  await view().get("#organization_slug").setValue("flight");
  await view().get("#org-form").trigger("submit");
  await flushHostUpdates();
}
test("core administration creation uses a scoped visit and displays a successful organization", async () => {
  await start();
  await click("/admin/organizations/new");
  await reply(0, platformCreationSnapshot());
  const shell = view().get("#sidebar-drawer").element;
  expect(view().find("#host-route-unavailable").exists()).toBe(false);
  await submitPlatformOrganization();
  expect(transport.requests[1]).toMatchObject({
    event: "host:platform-administration",
    payload: {
      path: "/admin/organizations/new",
      event: "create",
      token: "visit-u-1",
      input: { display_name: "Flight", slug: "flight" },
    },
  });
  const organization = { id: "org-new", name: "Flight", slug: "flight" };
  await reply(1, {
    status: "created",
    organization,
    host: platformCreationSnapshot("u-1", organization),
  });
  expect(view().get("#admin-organization-created-link").attributes("href")).toBe(
    "/admin/organizations/org-new",
  );
  expect(view().get("#sidebar-drawer").element).toBe(shell);
  expect(view().find("#org-form").exists()).toBe(false);
});
test("late organization creation cannot replace a later page or another administrator draft", async () => {
  await start();
  await click("/admin/organizations/new");
  await reply(0, platformCreationSnapshot());
  await submitPlatformOrganization();
  await click("/missions");
  await reply(2, snapshot("/missions"));
  const organization = { id: "org-new", name: "Flight", slug: "flight" };
  await reply(1, {
    status: "created",
    organization,
    host: platformCreationSnapshot("u-1", organization),
  });
  expect(view().find("#mission-list-table").exists()).toBe(true);
  expect(view().find("#admin-organization-created").exists()).toBe(false);
  await click("/admin/organizations/new");
  await reply(3, platformCreationSnapshot());
  await submitPlatformOrganization();
  await view().setProps({ snapshot: platformCreationSnapshot("u-2") });
  await flushHostUpdates();
  await reply(4, {
    status: "created",
    organization,
    host: platformCreationSnapshot("u-1", organization),
  });
  expect(view().find("#admin-organization-created").exists()).toBe(false);
  expect(
    view().get<HTMLInputElement | HTMLSelectElement>("#organization_display_name").element.value,
  ).toBe("");
  expect(view().find("#admin-organization-create-message").exists()).toBe(false);
});

test("a refreshed administration visit token rejects an older same-user creation response", async () => {
  await start();
  await click("/admin/organizations/new");
  await reply(0, platformCreationSnapshot());
  await submitPlatformOrganization();
  const refreshed = platformCreationSnapshot();
  refreshed.platform_administration_page.action_token = "replacement-visit";
  await view().setProps({ snapshot: refreshed });
  await flushHostUpdates();
  const organization = { id: "old-org", name: "Old result", slug: "old-result" };
  await reply(1, {
    status: "created",
    organization,
    host: platformCreationSnapshot("u-1", organization),
  });
  expect(view().find("#admin-organization-created").exists()).toBe(false);
  expect(view().get("#admin-organization-create-message").text()).toContain("unknown");
});

function platformOrganizationSnapshot(
  page: "organization_detail" | "organization_invite",
  userId = "u-1",
  token = "detail-visit",
) {
  const path = `/admin/organizations/org-a${page === "organization_invite" ? "/invite" : ""}`;
  const value = snapshot(path);
  value.context.user.user_id = userId;
  const data = {
    version: 1,
    user_id: userId,
    observed_at: "2026-09-10T01:00:00Z",
    organization: { id: "org-a", name: "Flight organization", slug: "flight" },
    ...(page === "organization_invite"
      ? { submitted: null }
      : {
          limit: 25,
          query: { members_after: "", invitations_after: "", services_after: "" },
          issued_identity: null,
          members: { entries: [], next_after: null },
          invitations: { entries: [], next_after: null },
          services: { entries: [], next_after: null },
        }),
  };
  return {
    ...value,
    platform_administration_page: {
      version: 1,
      page,
      status: "ready",
      user_id: userId,
      organization_id: "org-a",
      action_token: token,
      data,
    },
  };
}
for (const page of ["organization_detail", "organization_invite"] as const) {
  for (const change of ["navigation", "user", "token"]) {
    test(`${page} discards its action result after ${change} changes`, async () => {
      await start();
      const original = platformOrganizationSnapshot(page);
      await click(original.path);
      await reply(0, original);
      const issue = page === "organization_detail";
      if (issue) {
        const form = view().get("#open-organization-form");
        const event = new Event("submit", { bubbles: true, cancelable: true });
        form.element.dispatchEvent(event);
        expect(event.defaultPrevented).toBe(false);
        await view().get("#service_identity_display_name").setValue("Flight API");
        await view().get("#service_identity_id").setValue("svc-new");
      } else {
        await view().get("#invite_email").setValue("recipient@example.test");
      }
      await view()
        .get(issue ? "#service-identity-form" : "#invite-form")
        .trigger("submit");
      await flushHostUpdates();
      expect(transport.requests[1]).toMatchObject({
        event: "host:platform-administration",
        payload: {
          path: original.path,
          token: "detail-visit",
          event: issue ? "issue_service_identity" : "invite",
        },
      });
      if (change === "navigation") {
        await click("/missions");
        await reply(2, snapshot("/missions"));
      } else {
        await view().setProps({
          snapshot: platformOrganizationSnapshot(
            page,
            change === "user" ? "u-2" : "u-1",
            "replacement-visit",
          ),
        });
        await flushHostUpdates();
      }
      const result = issue
        ? {
            status: "issued",
            identity: {
              id: "svc-new",
              name: "Flight API",
              api_token: "stale-ephemeral-test-token",
            },
          }
        : {
            status: "invited",
            invitation: {
              id: "invite-new",
              email: "recipient@example.test",
              role: "member",
              grant_platform_admin: false,
              expires_at: "2026-09-20T01:00:00Z",
              delivery: "submitted",
            },
          };
      await reply(1, { ...result, host: original });
      expect(view().find("#issued-service-token").exists()).toBe(false);
      expect(view().text()).not.toContain("stale-ephemeral-test-token");
      expect(view().find("#organization-invitation-created").exists()).toBe(false);
      if (change === "navigation") expect(view().find("#mission-list-table").exists()).toBe(true);
    });
  }
}

// Render every catalog entry, so adding a kind without a host branch fails visibly.
const routeComponents = {
  settings: "SettingsPage",
  administration: "AdministrationPage",
  mission: "MissionPage",
  organization_module: "OrganizationModulePage",
  spacecraft: "SpacecraftPage",
  spacecraft_module: "SpacecraftModulePage",
  catalog: "CatalogPage",
  mission_module: "MissionModulePage",
  ops_module: "OpsModulePage",
  activation_approvals: "ActivationApprovalsPage",
  notifications: "NotificationsPage",
  platform_administration: "PlatformAdministrationPage",
  administration_diagnostics: "AdministrationDiagnosticsPage",
  application_management: "InstallationManagementPage",
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
  const route = required(routes.find((route) => route.path === "/missions"));
  const kind = route.kind;
  try {
    route.kind = "unsupported-test-kind";
    wrapper = mount(BrowserHost, {
      props: { snapshot: snapshot("/missions") },
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
  const state = reactive(snapshot("/missions", null));
  wrapper = mount(BrowserHost, { props: { snapshot: state } });
  await flushPromises();
  state.context.organization.display_name = "Patched organization";
  await nextTick();
  expect(wrapper.text()).toContain("Patched organization");
});
