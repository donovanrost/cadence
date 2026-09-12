import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import ExplorationPanel from "./ExplorationPanel.vue";
import { context, fixture, selectedFixture } from "./fixtures.test-support";
import { explorationHref } from "./query";
import { readExploration } from "./validation";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => wrappers.splice(0).forEach((w) => w.unmount()));
function setup(model = fixture(), refresh = vi.fn().mockResolvedValue(undefined)) {
  const port = {
    execute: vi.fn(),
    navigate: vi.fn((_: string) => {}),
    guardNavigation: vi.fn((_guard: () => boolean) => vi.fn()),
  };
  const wrapper = mount(ExplorationPanel, { props: { model, context, port, refresh } });
  wrappers.push(wrapper);
  return { wrapper, port, refresh };
}
test("renders real observations with exact timestamps and no nested main landmark", () => {
  const { wrapper, port } = setup();
  expect(wrapper.get("#exploration-results tbody tr").text()).toContain("4.2");
  expect(wrapper.get("#exploration-results time").attributes("datetime")).toBe(
    "2026-09-07T11:59:59.654321Z",
  );
  expect(wrapper.get("#exploration-results").text()).toContain("binding-a");
  expect(wrapper.find("main").exists()).toBe(false);
  const ids = wrapper.findAll("[id]").map((node) => node.attributes("id"));
  expect(new Set(ids).size).toBe(ids.length);
  expect(port.execute).not.toHaveBeenCalled();
});
test("submitting filters preserves source and origin context and clears a different point's sample", async () => {
  const model = fixture();
  model.query.sample_id = "old-sample";
  model.inspection = { status: "not_found", sample: null };
  model.query.selected_time = "2026-09-07T11:00:00.000001Z";
  const { wrapper, port } = setup(model);
  await wrapper.get("#exploration-point-id").setValue("HK.current+raw");
  await wrapper.get("#exploration-query").trigger("submit");
  const url = new URL(required(port.navigate.mock.calls[0])[0], "https://cadence.test");
  expect(url.searchParams.get("point_id")).toBe("HK.current+raw");
  expect(url.searchParams.get("source_binding_id")).toBe("binding-a");
  expect(url.searchParams.get("source_dashboard_id")).toBe("origin");
  expect(url.searchParams.has("sample_id")).toBe(false);
  expect(url.searchParams.has("selected_time")).toBe(false);
  expect(port.execute).not.toHaveBeenCalled();
});
test("following a sample freezes the executed window and clearing selection keeps origin context", async () => {
  const { wrapper, port } = setup();
  await wrapper.get("#exploration-results button").trigger("click");
  const url = new URL(required(port.navigate.mock.calls[0])[0], "https://cadence.test");
  expect(url.searchParams.get("sample_id")).toBe("sample/one");
  expect(url.searchParams.get("selected_time")).toBe("2026-09-07T11:59:59.654321Z");
  expect(url.searchParams.get("time_mode")).toBe("range");
  expect(url.searchParams.get("from")).toBe("2026-09-07T11:00:00.123456Z");
  expect(url.searchParams.get("selected_data_source_id")).toBe("source-a");
  expect(url.searchParams.get("selected_source_binding_id")).toBe("binding-a");
  expect(url.searchParams.has("data_source_id")).toBe(false);
  const next = selectedFixture();
  next.query = Object.fromEntries(url.searchParams);
  await wrapper.setProps({ model: next });
  await wrapper.get("#exploration-clear-selection").trigger("click");
  const cleared = new URL(required(port.navigate.mock.calls[1])[0], "https://cadence.test");
  expect(cleared.searchParams.has("sample_id")).toBe(false);
  expect(cleared.searchParams.has("selected_data_source_id")).toBe(false);
  expect(cleared.searchParams.has("selected_source_binding_id")).toBe(false);
  expect(cleared.searchParams.get("source_binding_id")).toBe("binding-a");
  expect(cleared.searchParams.get("source_dashboard_id")).toBe("origin");
});
test("historical row selection pins inspection without replacing the query source context", async () => {
  const model = fixture();
  model.rows.push({
    ...required(model.rows[0]),
    key: "b".repeat(64),
    source: { ...required(model.rows[0]).source, data_source_id: "source-b" },
  });
  const { wrapper, port } = setup(model);
  await required(wrapper.findAll("#exploration-results button")[1]).trigger("click");
  const query = Object.fromEntries(
    new URL(required(port.navigate.mock.calls[0])[0], "https://cadence.test").searchParams,
  );
  expect(query.source_binding_id).toBe("binding-a");
  expect(query.data_source_id).toBeUndefined();
  expect(query.selected_data_source_id).toBe("source-b");
  const selected = selectedFixture();
  if (selected.inspection.status !== "ready") throw Error("fixture must be ready");
  selected.rows = model.rows;
  selected.query = { ...query, selected_time: "2026-09-07T13:59:59.654321+02:00" };
  selected.inspection.sample.source.data_source_id = "source-b";
  await wrapper.setProps({ model: selected });
  const rows = wrapper.findAll("#exploration-results tbody tr");
  expect(required(rows[0]).classes()).not.toContain("bg-primary/10");
  expect(required(rows[1]).classes()).toContain("bg-primary/10");
});
test("unsupported and empty results leave the query controls usable", async () => {
  const model = fixture();
  model.rows = [];
  model.status = "unsupported_exploration_scope";
  const { wrapper } = setup(model);
  expect(wrapper.get("#exploration-result-state").text()).toContain("No broader query");
  expect(wrapper.get("#exploration-apply").attributes("disabled")).toBeUndefined();
  await wrapper.setProps({ model: { ...model, status: "empty" } });
  expect(wrapper.get("#exploration-result-state").text()).toContain("no observations");
});
test("failed refresh hides old rows and a pending read prevents duplicate work and navigation", async () => {
  let reject!: (reason?: unknown) => void;
  const refresh = vi.fn(
    () =>
      new Promise<void>((_resolve, fail) => {
        reject = fail;
      }),
  );
  const { wrapper, port } = setup(selectedFixture(), refresh);
  await wrapper.get("#exploration-reload").trigger("click");
  await wrapper.get("#exploration-reload").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  expect(wrapper.get("#exploration-clear-selection").attributes("disabled")).toBeDefined();
  expect(required(port.guardNavigation.mock.calls[0])[0]()).toBe(false);
  expect(wrapper.get("#exploration-open-origin").attributes("aria-disabled")).toBe("true");
  await wrapper.get("#exploration-open-origin").trigger("click");
  expect(port.navigate).not.toHaveBeenCalled();
  reject(Error("offline"));
  await flushPromises();
  expect(wrapper.find("#exploration-results").exists()).toBe(false);
  expect(wrapper.find("#exploration-sample-details").exists()).toBe(false);
  expect(wrapper.find("#exploration-origin").exists()).toBe(false);
  expect(wrapper.get("#exploration-refresh-failed").attributes("role")).toBe("alert");
});
test("origin navigation uses an admitted published dashboard without reinterpreting Explore filters", async () => {
  const model = selectedFixture();
  model.query.source_dashboard_id = "dashboard/one+two";
  model.origin = { status: "ready", dashboard: { id: "dashboard/one+two", name: "<img src=x>" } };
  const { wrapper, port } = setup(model);
  const link = wrapper.get("#exploration-open-origin");
  expect(link.attributes("href")).toBe("/missions/mission/ops/dashboards/dashboard%2Fone%2Btwo");
  expect(wrapper.get("#exploration-origin").text()).toContain("Explore filters are not applied");
  expect(wrapper.find("#exploration-origin img").exists()).toBe(false);
  await link.trigger("click", { ctrlKey: true });
  expect(port.navigate).not.toHaveBeenCalled();
  await link.trigger("click");
  expect(port.navigate).toHaveBeenCalledExactlyOnceWith(link.attributes("href"));
  expect(port.execute).not.toHaveBeenCalled();
  await wrapper.setProps({
    model: { ...model, origin: { status: "unavailable", dashboard: null } },
  });
  expect(wrapper.find("#exploration-open-origin").exists()).toBe(false);
  expect(wrapper.get("#exploration-origin-unavailable").attributes("role")).toBe("status");
  expect(wrapper.find("#exploration-results").exists()).toBe(true);
  const direct = fixture();
  delete direct.query.source_dashboard_id;
  direct.origin = { status: "not_provided", dashboard: null };
  await wrapper.setProps({ model: direct });
  expect(wrapper.find("#exploration-origin").exists()).toBe(false);
});
test("origin references reject arbitrary URLs, foreign identities and inconsistent states", () => {
  const model = fixture();
  const invalid = [
    { ...model, version: 2 },
    { ...model, origin: { status: "ready", dashboard: { id: "foreign", name: "Other" } } },
    {
      ...model,
      origin: {
        status: "ready",
        dashboard: { id: "origin", name: "Other", href: "https://external.test" },
      },
    },
    { ...model, origin: { status: "ready", dashboard: null } },
    { ...model, origin: { status: "not_provided", dashboard: null } },
    { ...model, origin: { status: "unavailable", dashboard: model.origin.dashboard } },
    {
      ...model,
      query: { ...model.query, source_dashboard_id: ".." },
      origin: { status: "ready", dashboard: { id: "..", name: "Other" } },
    },
    { ...model, query: {}, origin: model.origin },
  ];
  for (const value of invalid) expect(() => readExploration(value, context)).toThrow();
});
test("contract rejects extra metadata, mismatched scope, malformed values and oversized results", () => {
  const model = fixture();
  expect(readExploration(model, context)).toBe(model);
  expect(() => readExploration(model, { ...context, missionId: "foreign" })).toThrow();
  const invalid = [
    { ...model, version: 1 },
    { ...model, raw_metadata: {} },
    { ...model, rows: [...model.rows, ...model.rows] },
    { ...model, query: { ...model.query, mission_id: "other" } },
    { ...model, rows: [{ ...required(model.rows[0]), value: Infinity }] },
    { ...model, rows: [{ ...required(model.rows[0]), value: { credentials: "private" } }] },
    { ...model, rows: [{ ...required(model.rows[0]), sample_id: 123 }] },
    { ...model, rows: [{ ...required(model.rows[0]), time: "invalid" }] },
    { ...model, warnings: [{ code: "failed", severity: "error", message: "private" }] },
  ];
  for (const value of invalid) expect(() => readExploration(value, context)).toThrow();
});
test("shows exact stored values, clocks and provenance without interpreting markup", async () => {
  const model = selectedFixture();
  if (model.inspection.status !== "ready") throw Error("fixture must be ready");
  model.inspection.sample.raw_value.text = '"<img src=x onerror=alert(1)>"';
  model.inspection.sample.engineering_value.text = "9007199254740993";
  const { wrapper } = setup(model);
  expect(wrapper.get("#exploration-sample-raw_value").text()).toBe(
    '"<img src=x onerror=alert(1)>"',
  );
  expect(wrapper.find("#exploration-sample-details img").exists()).toBe(false);
  expect(wrapper.get("#exploration-sample-engineering_value").text()).toBe("9007199254740993");
  expect(wrapper.get("#exploration-sample-receipt").attributes("datetime")).toBe(
    "2026-09-07T11:59:59.654321Z",
  );
  expect(wrapper.get("#exploration-sample-generation").text()).toBe("2026-09-07T11:59:58.123456Z");
  expect(wrapper.get("#exploration-sample-source").text()).toBe("source-a");
  expect(wrapper.get("#exploration-sample-validity").text()).toBe("superseded");
  const ids = wrapper.findAll("[id]").map((node) => node.attributes("id"));
  expect(new Set(ids).size).toBe(ids.length);
  for (const status of [
    "not_found",
    "ambiguous",
    "unsupported",
    "timeout",
    "unavailable",
  ] as const) {
    await wrapper.setProps({ model: { ...model, inspection: { status, sample: null } } });
    expect(wrapper.find("#exploration-sample-details").exists()).toBe(false);
    expect(wrapper.get("#exploration-sample-state").attributes("role")).toBe("status");
    expect(wrapper.find("#exploration-results").exists()).toBe(true);
  }
});
test("links encode path segments and preserve microseconds, plus signs and source identity", () => {
  const model = fixture();
  model.mission_id = "mission/one";
  model.query = {
    point_id: "point+one",
    from: "2026-09-07T11:00:00.123456+02:00",
    source_binding_id: "binding/a",
  };
  const url = new URL(explorationHref(model), "https://cadence.test");
  expect(url.pathname).toBe("/missions/mission%2Fone/ops/explore");
  expect(Object.fromEntries(url.searchParams)).toEqual(model.query);
});
