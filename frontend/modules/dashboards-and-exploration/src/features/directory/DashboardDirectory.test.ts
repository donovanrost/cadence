import { afterEach, expect, test, vi } from "vite-plus/test";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { flushPromises, mount } from "@vue/test-utils";
import DashboardDirectory from "./DashboardDirectory.vue";
import { directoryContribution } from "./contribution";
import type { DirectoryPage } from "./contracts";
import { directoryFixture, row } from "./fixtures.test-support";
import { directoryHref } from "./href";

const context = { organizationId: "org-1", missionId: "mission-1" };
let wrapper: ReturnType<typeof mount> | undefined;
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  document.body.innerHTML = "";
});

function envelope(page: DirectoryPage) {
  return { status: "ready", data: page };
}

function render(page = directoryFixture(), execute = vi.fn(async (): Promise<unknown> => null)) {
  const navigate = vi.fn((_: string) => {});
  const header = pageHeaderHarness("/missions/:mission_id/ops/dashboards");
  wrapper = mount(DashboardDirectory, {
    attachTo: document.body,
    props: { page, context, port: { execute, navigate }, refresh: async () => {} },
    global: { provide: header.provide },
  });
  return { app: wrapper, execute, navigate, header };
}

test("reads only the current mission's version 2 directory", () => {
  expect(directoryContribution.read(directoryFixture(), context).page.model.rows).toHaveLength(2);
  const broken: ((page: DirectoryPage & Record<string, unknown>) => void)[] = [
    (p) => Object.assign(p.model, { version: 1 }),
    (p) => Object.assign(p.model, { mission_id: "foreign" }),
    (p) => Object.assign(p.model, { total: 51 }),
    (p) => Object.assign(p.model.filters, { sort: "widgets" }),
    (p) => Object.assign(p.model.rows[1] ?? {}, { id: "dashboard-1" }),
    (p) => Object.assign(p.model.rows[0] ?? {}, { updated_at: "yesterday" }),
    (p) => Object.assign(p, { phase: "editing" }),
    (p) => Object.assign(p, { sequence: -1 }),
  ];
  for (const change of broken) {
    const page = directoryFixture();
    change(page);
    expect(() => directoryContribution.read(page, context)).toThrow();
  }
  expect(() =>
    directoryContribution.read(directoryFixture(), { ...context, resourceId: "x" }),
  ).toThrow();
});

test("lists dashboards with shortcuts, links names and filters by a row's tag", async () => {
  const { app, navigate, header } = render();
  expect(header.href("import")).toBe("/missions/mission-1/ops/dashboards/new?mode=import");
  const list = app.get("[aria-label=Dashboards]");
  expect(list.findAll("li")).toHaveLength(2);
  expect(list.get("li a").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1",
  );
  expect(list.text()).toContain("Dana Rost");
  expect(app.get("#dashboard-directory-shortcuts").text()).toContain("Pass Overview");
  await list.get("button[title='Filter by eps']").trigger("click");
  expect(navigate).toHaveBeenCalledWith(directoryHref("mission-1", { tags: ["eps"] }));
});

test("search is debounced into the URL; filtered views hide the shortcuts", async () => {
  vi.useFakeTimers();
  const filtered = directoryFixture();
  filtered.model.filters.query = "power";
  const { app, navigate } = render(filtered);
  expect(app.find("#dashboard-directory-shortcuts").exists()).toBe(false);
  await app.get("#dashboard-directory-search").setValue("pass");
  expect(navigate).not.toHaveBeenCalled();
  vi.advanceTimersByTime(300);
  expect(navigate).toHaveBeenCalledWith("/missions/mission-1/ops/dashboards?query=pass");
});

test("star is a sequenced effect that adopts the confirmed page", async () => {
  const confirmed = directoryFixture();
  confirmed.sequence = 1;
  confirmed.model.rows = confirmed.model.rows.map((r) => ({ ...r, starred: true }));
  const execute = vi.fn(async (): Promise<unknown> => ({
    status: "ok",
    page: envelope(confirmed),
    result: { dashboard_id: "dashboard-2" },
  }));
  const { app } = render(directoryFixture(), execute);
  await app.get("[aria-label='Star Power Bus']").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("star", {
    sequence: 1,
    command: { dashboard_id: "dashboard-2", starred: true },
  });
  expect(app.get("#dashboard-dashboard-2").attributes("data-starred")).toBe("true");
});

test("an unconfirmed effect is reported and leaves the page as it was", async () => {
  const { app } = render(
    directoryFixture(),
    vi.fn(async (): Promise<unknown> => ({ status: "unknown" })),
  );
  await app.get("[aria-label='Star Power Bus']").trigger("click");
  await flushPromises();
  expect(app.get("#dashboard-directory-notice").text()).toContain("could not be confirmed");
  expect(app.get("#dashboard-dashboard-2").attributes("data-starred")).toBe("false");
});

test("someone else's change to the same view is highlighted; viewers get no authoring", async () => {
  const { app } = render();
  const next = directoryFixture();
  next.model.rows = [row("dashboard-3", { name: "Conjunction Watch" }), ...next.model.rows];
  next.model.total = 3;
  await app.setProps({ page: next });
  expect(app.get("#dashboard-dashboard-3").classes()).toContain("bg-primary/10");
  expect(app.get("#dashboard-dashboard-1").classes()).not.toContain("bg-primary/10");

  const viewer = directoryFixture();
  viewer.model.author = false;
  wrapper?.unmount();
  const second = render(viewer);
  expect(second.header.has("new")).toBe(false);
  expect(second.header.href("library")).toBe("/missions/mission-1/ops/dashboards/library");
  expect(second.app.find("[aria-label^='Actions for']").exists()).toBe(false);
});

test("a mission without dashboards offers creation and archived dashboards", () => {
  const empty = directoryFixture();
  Object.assign(empty.model, { rows: [], total: 0, available_tags: [] });
  empty.model.shortcuts = { starred: [], recent: [] };
  const { app } = render(empty);
  expect(app.get("#dashboard-directory-first-run").text()).toContain("No dashboards yet");
  expect(app.find("[aria-label=Dashboards]").exists()).toBe(false);
});
