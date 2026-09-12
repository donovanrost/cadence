import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import DashboardDirectory from "./DashboardDirectory.vue";
import { directoryContribution } from "./contribution";
import { directoryFixture } from "./fixtures.test-support";
let wrapper: ReturnType<typeof mount> | undefined;
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  document.body.innerHTML = "";
});
function render(
  execute = vi.fn(async () => ({
    status: "ok",
    sequence: 1,
    data: { dashboard_id: "dashboard-1", starred: false },
  })),
) {
  const state = directoryFixture(),
    navigate = vi.fn(),
    refresh = vi.fn(async () => {});
  wrapper = mount(DashboardDirectory, {
    attachTo: document.body,
    props: { state, port: { execute, navigate }, refresh },
  });
  return { state, navigate, execute, refresh, app: wrapper };
}
test("validates context, lifecycle, pagination, row identities and supported DTO versions", () => {
  const context = { organizationId: "org-1", missionId: "mission-1" };
  expect(directoryContribution.read(directoryFixture(), context)).toHaveProperty("state");
  for (const change of [
    (s: any) => {
      s.model.version = 2;
    },
    (s: any) => {
      s.model.mission_id = "foreign";
    },
    (s: any) => {
      s.model.rows[1].id = s.model.rows[0].id;
    },
    (s: any) => {
      s.model.rows[0].lifecycle = "arbitrary";
    },
    (s: any) => {
      s.model.total = 51;
    },
    (s: any) => {
      s.model.rows[0].version = 1.5;
    },
    (s: any) => {
      s.sequence = -1;
    },
    (s: any) => {
      s.phase = "complete";
    },
  ]) {
    const state = directoryFixture();
    change(state);
    expect(() => directoryContribution.read(state, context)).toThrow();
  }
});
test("keeps real dashboard links, personal stars, author controls and URL filters", async () => {
  vi.useFakeTimers();
  const { app, navigate } = render();
  expect(app.get("#open-dashboard-1").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1",
  );
  expect(app.get("#star-dashboard-1").attributes("aria-pressed")).toBe("true");
  expect(app.find("#open-dashboard-2").exists()).toBe(false);
  expect(app.get("#restore-dashboard-2").attributes("disabled")).toBeUndefined();
  await app.get("#directory_query").setValue("thermal & flight");
  await vi.advanceTimersByTimeAsync(250);
  expect(navigate).toHaveBeenCalledOnce();
  const url = new URL(navigate.mock.calls[0][0], "http://localhost");
  expect(url.searchParams.get("query")).toBe("thermal & flight");
  expect(url.searchParams.get("page")).toBe("1");
});
test("sends observed version and ordered effects, then refreshes without replacing native filters", async () => {
  const { app, execute, refresh, state } = render();
  const input = app.get("#directory_query").element;
  refresh.mockImplementation(async () => {
    await app.setProps({ state: { ...state, sequence: 1 } });
  });
  await app.get("#star-dashboard-1").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("star", {
    dashboard_id: "dashboard-1",
    expected_version: 3,
    sequence: 1,
    starred: false,
  });
  expect(refresh).toHaveBeenCalledOnce();
  expect(app.get("#directory_query").element).toBe(input);
  expect(app.get("#star-dashboard-1").attributes("disabled")).toBeUndefined();
});
test("uncertain effects stay locked across a host refresh and read-only recovery", async () => {
  const execute = vi.fn(async () => ({ status: "unknown", sequence: 1 }));
  const { app, refresh, state } = render(execute as any);
  await app.get("#restore-dashboard-2").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("restore", {
    dashboard_id: "dashboard-2",
    expected_version: 2,
    sequence: 1,
  });
  await app.setProps({ state: { ...state, sequence: 1, phase: "submitted" } });
  await app.get("#dashboard-directory-refresh").trigger("click");
  await flushPromises();
  expect(refresh).toHaveBeenCalledOnce();
  expect(app.get("#restore-dashboard-2").attributes("disabled")).toBeDefined();
  expect(app.get("#star-dashboard-1").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledOnce();
});
test("pagination links preserve filters and malformed confirmations cannot unlock actions", async () => {
  const execute = vi.fn(async () => ({
    status: "ok",
    sequence: 1,
    data: { dashboard_id: "dashboard-1", starred: true },
  }));
  const { app, state } = render(execute as any);
  await app.get("#star-dashboard-1").trigger("click");
  await flushPromises();
  expect(app.get("#star-dashboard-1").attributes("disabled")).toBeDefined();
  const paged = directoryFixture();
  paged.model.total = 51;
  paged.model.pages = 2;
  paged.model.filters.page = 2;
  paged.model.filters.query = "flight";
  paged.model.rows = [state.model.rows[0]];
  await app.setProps({ state: paged });
  const previous = new URL(
    app.get("#dashboard-directory-previous").attributes("href")!,
    "http://localhost",
  );
  expect(previous.searchParams.get("page")).toBe("1");
  expect(previous.searchParams.get("query")).toBe("flight");
  expect(app.find("#dashboard-directory-next").exists()).toBe(false);
});
test("known rejection permits correction and uses the server sequence", async () => {
  const execute = vi.fn(async () => ({ status: "rejected", sequence: 0 }));
  const { app } = render(execute as any);
  await app.get("#star-dashboard-1").trigger("click");
  await flushPromises();
  await app.get("#star-dashboard-1").trigger("click");
  await flushPromises();
  expect(execute.mock.calls[1]).toEqual([
    "star",
    { dashboard_id: "dashboard-1", expected_version: 3, sequence: 1, starred: false },
  ]);
});

test("authors open unpublished drafts in the editor and publication restores the viewer link", async () => {
  const { app, state } = render();
  const draft = structuredClone(state);
  draft.model.rows[0].published_version = null;
  await app.setProps({ state: draft });
  expect(app.get("#open-dashboard-1").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1/edit",
  );
  expect(app.get("#dashboard-dashboard-1").text()).toContain("Unpublished");
  await app.setProps({ state: { ...draft, model: { ...draft.model, author: false } } });
  expect(app.get("#open-dashboard-1").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1",
  );
  await app.setProps({ state });
  expect(app.get("#open-dashboard-1").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1",
  );
});
