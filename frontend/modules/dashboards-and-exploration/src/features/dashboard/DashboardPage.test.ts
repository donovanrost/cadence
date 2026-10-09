import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { snapshotFixture } from "../workspace/snapshot-fixture.test-support";
import DashboardPage from "./DashboardPage.vue";
import { dashboardContribution } from "./contribution";
import { editPage, pageContext, viewPage } from "./fixtures.test-support";
import type { DashboardPageData } from "./contracts";

const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
});

function render(page: DashboardPageData) {
  const release = vi.fn();
  const port = {
    execute: vi.fn(
      async (_action: string, _input: Record<string, unknown>): Promise<unknown> => ({}),
    ),
    navigate: vi.fn((_href: string) => {}),
    guardNavigation: vi.fn((_guard: () => boolean) => release),
  };
  const app = mount(DashboardPage, {
    props: { page, context: pageContext, port, refresh: vi.fn(async () => {}) },
    attachTo: document.body,
  });
  apps.push(app);
  return { app, port, release };
}

test("the contribution decodes view and edit pages for this dashboard only", () => {
  expect(dashboardContribution.read(viewPage(), pageContext).page).toEqual(viewPage());
  expect(dashboardContribution.read(editPage(), pageContext).page).toEqual(editPage());
  expect(() =>
    dashboardContribution.read(viewPage(), { ...pageContext, resourceId: "other" }),
  ).toThrow();
  expect(() =>
    dashboardContribution.read(
      { ...editPage(), live: { active: true, refresh_ms: 2000 } },
      pageContext,
    ),
  ).toThrow();
});

test("an empty, unpublished dashboard renders for its author", async () => {
  const { app } = render(viewPage({ ...snapshotFixture(), sections: [], placements: [] }));
  await flushPromises();
  expect(app.text()).toContain("No widgets yet");
});
