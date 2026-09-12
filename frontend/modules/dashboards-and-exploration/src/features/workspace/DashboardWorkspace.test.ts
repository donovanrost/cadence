import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { workspaceContribution } from "./contribution";
import DashboardWorkspace from "./DashboardWorkspace.vue";
import { snapshotContext, snapshotFixture } from "./snapshot-fixture.test-support";
const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
});
function render(refresh = vi.fn(async () => {})) {
  const port = { execute: vi.fn(), navigate: vi.fn((_: string) => {}) };
  const model = snapshotFixture();
  const app = mount(DashboardWorkspace, {
    props: { model, context: snapshotContext, port, refresh },
    attachTo: document.body,
  });
  apps.push(app);
  return { app, port, model, refresh };
}
test("the public contribution accepts only matching published snapshots", () => {
  expect(workspaceContribution.read(snapshotFixture(), snapshotContext).model).toEqual(
    snapshotFixture(),
  );
  for (const document_mode of ["draft", "draft_preview"])
    expect(() =>
      workspaceContribution.read({ ...snapshotFixture(), document_mode }, snapshotContext),
    ).toThrow();
  expect(() =>
    workspaceContribution.read(snapshotFixture(), { ...snapshotContext, resourceId: "other" }),
  ).toThrow();
  expect(workspaceContribution.actions).toEqual([]);
});
test("the real viewer renders values, published identity, contextual controls and capability-gated links", async () => {
  const { app, model, port } = render();
  expect(app.get("#dashboard-viewer-title").text()).toBe(model.name);
  expect(app.get('[data-workspace-value="battery"]').text()).toBe("28.40");
  expect(app.get("#dashboard-viewer-version").text()).toBe("Published v1");
  expect(app.get("#dashboard-viewer-delivery").text()).toContain("Snapshot");
  expect(app.get("#dashboard-viewer-edit").attributes("href")).toBe(
    "/missions/mission/ops/dashboards/dashboard/edit",
  );
  await app.setProps({ model: { ...model, author: false } });
  expect(app.find("#dashboard-viewer-edit").exists()).toBe(false);
  expect(port.execute).not.toHaveBeenCalled();
});
test("applying context navigates through the host port and validates bounds without executing commands", async () => {
  const { app, port } = render();
  await app.get("#dashboard-viewer-from").setValue("2026-09-07T00:00:00Z");
  await app.get("#dashboard-viewer-to").setValue("2026-09-07T01:00:00Z");
  await app.get("#dashboard-viewer-axis").setValue("receipt_time");
  await app.get("#dashboard-viewer-context-form").trigger("submit");
  const url = new URL(required(port.navigate.mock.calls[0])[0], "http://cadence.test");
  expect(url.pathname).toBe("/missions/mission/ops/dashboards/dashboard");
  expect(url.searchParams.get("time_axis")).toBe("receipt_time");
  expect(url.searchParams.get("from")).toBe("2026-09-07T00:00:00Z");
  await app.get("#dashboard-viewer-from").setValue("2026-10-07T00:00:00Z");
  await app.get("#dashboard-viewer-context-form").trigger("submit");
  expect(app.find("#dashboard-viewer-error").exists()).toBe(true);
  expect(port.navigate).toHaveBeenCalledTimes(1);
  await app.get("#dashboard-viewer-mode").setValue("live");
  await app.get("#dashboard-viewer-context-form").trigger("submit");
  expect(
    new URL(required(port.navigate.mock.calls[1])[0], "http://cadence.test").searchParams.has(
      "from",
    ),
  ).toBe(false);
  expect(port.execute).not.toHaveBeenCalled();
});
test("diagnostics handoff preserves the displayed runtime context and rejects unsupported replay context", async () => {
  const { app, model } = render();
  const url = new URL(
    required(app.get("#dashboard-viewer-diagnostics").attributes("href")),
    "http://cadence.test",
  );
  expect(url.pathname).toBe("/missions/mission/ops/dashboards/dashboard/diagnostics");
  expect(url.searchParams.get("from")).toBe(model.context.from);
  expect(url.searchParams.get("to")).toBe(model.context.to);
  expect(url.searchParams.get("realm")).toBe(model.context.realm);
  expect(url.searchParams.get("selection_view")).toBe(model.context.data_view);
  expect(url.searchParams.get("limit_mode")).toBe(model.context.limit_mode);
  await app.setProps({
    model: { ...model, context: { ...model.context, time_mode: "replay_run" } },
  });
  expect(app.find("#dashboard-viewer-diagnostics").exists()).toBe(false);
  expect(app.find("#dashboard-viewer-diagnostics-unavailable").exists()).toBe(true);
});
test("refresh is single-flight, keeps the native canvas, and contains a rejected transport", async () => {
  let reject!: (reason: Error) => void;
  const refresh = vi.fn(
    () =>
      new Promise<void>((_resolve, fail) => {
        reject = fail;
      }),
  );
  const { app, model } = render(refresh);
  const grid = app.get(".grid-stack").element;
  await app.get("#dashboard-viewer-refresh").trigger("click");
  await app.get("#dashboard-viewer-refresh").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  expect(app.get("#dashboard-viewer-apply").attributes("disabled")).toBeDefined();
  reject(Error("offline"));
  await flushPromises();
  expect(app.get("#dashboard-viewer-error").text()).toContain("could not be refreshed");
  await app.setProps({ model: structuredClone(model) });
  expect(app.get(".grid-stack").element).toBe(grid);
});
test("context timestamps preserve offsets and microseconds and reject calendar normalization", async () => {
  const { app, port } = render();
  const from = "2026-09-07T01:00:00.000001+01:00",
    to = "2026-09-07T00:00:00.000002Z";
  await app.get("#dashboard-viewer-from").setValue(from);
  await app.get("#dashboard-viewer-to").setValue(to);
  await app.get("#dashboard-viewer-context-form").trigger("submit");
  const query = new URL(required(port.navigate.mock.calls[0])[0], "http://cadence.test")
    .searchParams;
  expect(query.get("from")).toBe(from);
  expect(query.get("to")).toBe(to);
  for (const invalid of [
    "2026-02-31T00:00:00Z",
    "2026-09-07T00:00:00",
    "2026-09-07T00:00:00.000003Z",
    "2026-09-07T00:00:00.0000001Z",
  ]) {
    await app.get("#dashboard-viewer-from").setValue(invalid);
    await app.get("#dashboard-viewer-context-form").trigger("submit");
    expect(app.find("#dashboard-viewer-error").exists()).toBe(true);
  }
  expect(port.navigate).toHaveBeenCalledOnce();
});
