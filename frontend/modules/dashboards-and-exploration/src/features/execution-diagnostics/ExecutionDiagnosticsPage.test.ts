import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import ExecutionDiagnosticsPage from "./ExecutionDiagnosticsPage.vue";
import { executionDiagnosticsContribution } from "./contribution";
import { diagnosticsPageFixture, diagnosticContext } from "./fixtures.test-support";
import { diagnosticsHref, readDiagnosticsPage, readRuntimeQuery } from "./page-state";
const wrappers: ReturnType<typeof mount>[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.restoreAllMocks();
});
function setup(
  state = diagnosticsPageFixture(),
  execute = vi.fn(async (): Promise<unknown> => {
    throw Error("Lost response");
  }),
) {
  const navigate = vi.fn(),
    refresh = vi.fn(async () => {}),
    dispose = vi.fn();
  let guard = () => true;
  const wrapper = mount(ExecutionDiagnosticsPage, {
    props: {
      state,
      context: diagnosticContext,
      refresh,
      port: {
        execute,
        navigate,
        guardNavigation(fn) {
          guard = fn;
          return dispose;
        },
      },
    },
  });
  wrappers.push(wrapper);
  return { wrapper, execute, navigate, refresh, dispose, canLeave: () => guard() };
}
test("the compiled contribution admits scoped state and finite runtime context", () => {
  const state = diagnosticsPageFixture();
  expect(executionDiagnosticsContribution.read(state, diagnosticContext).state).toEqual(state);
  expect(executionDiagnosticsContribution.actions).toEqual(["inspect"]);
  for (const change of [
    { sequence: -1 },
    { sequence: 1.5 },
    { sequence: 1000001 },
    { publication_changed: "true" },
    { model: null },
    { runtime_query: { source_binding_id: "forged" } },
    { extra: true },
  ])
    expect(() => readDiagnosticsPage({ ...state, ...change }, diagnosticContext)).toThrow();
  expect(() =>
    readDiagnosticsPage(state, { ...diagnosticContext, resourceId: "foreign" }),
  ).toThrow();
  for (const query of [
    { time_mode: "replay_run" },
    { time_mode: "range" },
    { time_mode: "live", from: "x" },
    { realm: "other" },
    { to: {} },
    { time_mode: "range", from: "2026-02-30T00:00:00Z", to: "2026-03-03T00:00:00Z" },
  ])
    expect(() => readRuntimeQuery(query)).toThrow();
});
test("selection URLs preserve exact admitted time context without running an inspection", async () => {
  const state = diagnosticsPageFixture();
  state.runtime_query = {
    time_mode: "range",
    from: "2026-09-07T01:00:00.000001+01:00",
    to: "2026-09-07T00:00:00.000002Z",
    realm: "rehearsal",
  };
  const { wrapper, navigate, execute } = setup(state);
  await wrapper.get("#diagnostics-collection-frames").trigger("click");
  const url = new URL(navigate.mock.calls[0][0], "http://cadence.test");
  expect(url.pathname).toBe("/missions/mission/ops/dashboards/dashboard/diagnostics");
  expect(Object.fromEntries(url.searchParams)).toEqual({
    ...state.runtime_query,
    collection: "frames",
  });
  expect(execute).not.toHaveBeenCalled();
  await wrapper.setProps({
    state: { ...state, selection: { ...state.selection, collection: "frames" } },
  });
  expect(wrapper.get("#diagnostics-collection-frames").attributes("aria-current")).toBe("true");
  expect(wrapper.get("#diagnostics-loaded-at").attributes("datetime")).toBe(state.model.loaded_at);
  await wrapper.setProps({ state });
  expect(wrapper.get("#diagnostics-collection-plan").attributes("aria-current")).toBe("true");
  expect(
    new URL(
      wrapper.get("#diagnostics-viewer").attributes("href")!,
      "http://cadence.test",
    ).searchParams.get("from"),
  ).toBe(state.runtime_query.from);
});
test("explicit refresh is single flight, guards navigation and accepts only the next confirmed state", async () => {
  let resolve!: (value: unknown) => void;
  const state = diagnosticsPageFixture();
  state.publication_changed = true;
  const { wrapper, execute, canLeave, dispose } = setup(
    state,
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  expect(wrapper.find("#diagnostics-publication-changed").exists()).toBe(true);
  await wrapper.get("#diagnostics-inspect").trigger("click");
  await wrapper.get("#diagnostics-inspect").trigger("click");
  expect(execute).toHaveBeenCalledExactlyOnceWith("inspect", { sequence: 1 });
  expect(canLeave()).toBe(false);
  expect(wrapper.get("fieldset").attributes("disabled")).toBeDefined();
  const next = diagnosticsPageFixture();
  next.sequence = 1;
  next.model.document_version = 2;
  resolve({ status: "ok", state: next });
  await flushPromises();
  expect(wrapper.find("#diagnostics-publication-changed").exists()).toBe(false);
  expect(wrapper.get("#diagnostics-inspection-notice").text()).toContain("New inspection loaded");
  expect(canLeave()).toBe(true);
  wrapper.unmount();
  wrappers.splice(wrappers.indexOf(wrapper), 1);
  expect(dispose).toHaveBeenCalledOnce();
});
test("mismatched or unavailable replies hide retained evidence", async () => {
  for (const mutate of [
    (s: any) => s,
    (s: any) => ({ ...s, sequence: 2 }),
    (s: any) => ({ ...s, sequence: 1, publication_changed: true }),
    (s: any) => ({ ...s, sequence: 1, selection: { ...s.selection, collection: "frames" } }),
    (s: any) => ({ ...s, sequence: 1, runtime_query: { realm: "rehearsal" } }),
    (s: any) => ({ ...s, sequence: 1, model: null }),
  ]) {
    const { wrapper } = setup(
      diagnosticsPageFixture(),
      vi.fn(async () => ({ status: "ok", state: mutate(diagnosticsPageFixture()) })),
    );
    await wrapper.get("#diagnostics-inspect").trigger("click");
    await flushPromises();
    expect(wrapper.find("#diagnostics-page-unavailable").exists()).toBe(true);
    expect(wrapper.find("#execution-diagnostics-feature").exists()).toBe(false);
  }
});
test("recovery requires a successful host refresh with new authorized props", async () => {
  const { wrapper, refresh } = setup();
  await wrapper.get("#diagnostics-inspect").trigger("click");
  await flushPromises();
  await wrapper.get("#diagnostics-reload").trigger("click");
  await flushPromises();
  expect(wrapper.find("#diagnostics-page-unavailable").exists()).toBe(true);
  refresh.mockImplementationOnce(async () => {
    await wrapper.setProps({ state: { ...diagnosticsPageFixture(), sequence: 1 } });
  });
  await wrapper.get("#diagnostics-reload").trigger("click");
  await flushPromises();
  expect(wrapper.find("#diagnostics-page-unavailable").exists()).toBe(false);
  expect(wrapper.find("#execution-diagnostics-feature").exists()).toBe(true);
});
test("late responses are ignored after unmount and viewer links preserve native modified clicks", async () => {
  let resolve!: (v: unknown) => void;
  const { wrapper, navigate } = setup(
    diagnosticsPageFixture(),
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  await wrapper.get("#diagnostics-viewer").trigger("click", { ctrlKey: true });
  expect(navigate).not.toHaveBeenCalled();
  await wrapper.get("#diagnostics-viewer").trigger("click");
  expect(navigate).toHaveBeenCalledWith(diagnosticsHref(diagnosticsPageFixture()));
  await wrapper.get("#diagnostics-inspect").trigger("click");
  wrapper.unmount();
  wrappers.splice(wrappers.indexOf(wrapper), 1);
  resolve({ status: "ok", state: { ...diagnosticsPageFixture(), sequence: 1 } });
  await flushPromises();
});
