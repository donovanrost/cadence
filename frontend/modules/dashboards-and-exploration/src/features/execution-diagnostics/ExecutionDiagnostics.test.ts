import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import ExecutionDiagnostics from "./ExecutionDiagnostics.vue";
import DiagnosticIdentity from "./DiagnosticIdentity.vue";
import {
  diagnosticContext,
  diagnosticFixture,
  diagnosticWarningFixture,
} from "./fixtures.test-support";
import {
  initialSelection,
  matchingRows,
  readSelection,
  type DiagnosticSelection,
} from "./selection";

const wrappers: ReturnType<typeof mount>[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((wrapper) => wrapper.unmount());
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
function setup(model = diagnosticFixture(), selection = initialSelection()) {
  const wrapper = mount(ExecutionDiagnostics, {
    props: { model, context: diagnosticContext, selection },
  });
  wrappers.push(wrapper);
  return wrapper;
}
test("selection is exact and bounded independently of evidence admission", () => {
  expect(readSelection(initialSelection())).toEqual(initialSelection());
  for (const change of [
    { collection: "unknown" },
    { row: "raw-identity" },
    { row: "A".repeat(64) },
    { row: "a".repeat(64) + "\n" },
    { filter: "é".repeat(129) },
    { filter: "abc\n" },
    { filter: false },
    { identity: "unknown" },
  ])
    expect(() => readSelection({ ...initialSelection(), ...change })).toThrow();
  expect(() => readSelection(null)).toThrow();
  expect(readSelection({ ...initialSelection(), filter: "é".repeat(128) }).filter).toHaveLength(
    128,
  );
});
test("renders all seven collection controls and keeps the main landmark with the host", () => {
  const wrapper = setup();
  expect(wrapper.findAll("nav[aria-label='Diagnostic collections'] button")).toHaveLength(7);
  expect(wrapper.get("#diagnostics-collection-plan").attributes("aria-current")).toBe("true");
  expect(wrapper.find("main").exists()).toBe(false);
  expect(wrapper.get("#diagnostics-evidence-scope").text()).toContain(
    "do not reconstruct an earlier viewer session",
  );
  expect(wrapper.find("#diagnostics-select-prompt").exists()).toBe(true);
});
test("collection and row controls emit view state without replacing loaded evidence", async () => {
  const model = diagnosticFixture();
  const frozen = JSON.stringify(model);
  const wrapper = setup(model);
  await wrapper.get(`#diagnostics-row-${"a".repeat(64)}`).trigger("click");
  const selected = wrapper.emitted("select")![0][0] as DiagnosticSelection;
  expect(selected).toEqual({ ...initialSelection(), row: "a".repeat(64) });
  await wrapper.setProps({ selection: selected });
  expect(wrapper.get("#diagnostic-identity").element).toHaveProperty("value", "dashboard");
  expect(wrapper.get('[data-diagnostic-field="snapshot"]').text()).toBe("false");
  expect(wrapper.get('[data-diagnostic-field="warnings"]').text()).toBe("0");
  await wrapper.get("#diagnostics-collection-requests").trigger("click");
  expect(wrapper.emitted("select")![1][0]).toEqual({
    collection: "requests",
    row: null,
    filter: "",
  });
  expect(wrapper.get("#diagnostics-loaded-at").attributes("datetime")).toBe(model.loaded_at);
  expect(JSON.stringify(model)).toBe(frozen);
});
test("plan warnings can be filtered, selected and copied without rerunning the inspection", async () => {
  const model = diagnosticFixture();
  const warning = diagnosticWarningFixture();
  model.collections[0].rows.push(warning);
  const before = JSON.stringify(model);
  const wrapper = setup(model);
  await wrapper.get("#diagnostics-filter").setValue("stale_data");
  await wrapper.get("#diagnostics-filter-form").trigger("submit");
  await wrapper.setProps({ selection: wrapper.emitted("select")![0][0] as DiagnosticSelection });
  expect(wrapper.findAll("#diagnostics-rows li")).toHaveLength(1);
  await wrapper.get(`#diagnostics-row-${warning.id}`).trigger("click");
  await wrapper.setProps({ selection: wrapper.emitted("select")![1][0] as DiagnosticSelection });
  expect(wrapper.get('[data-diagnostic-field="warning_code"]').text()).toBe("stale_data");
  expect(wrapper.get('[data-diagnostic-field="placement_id"]').text()).toBe("placement/1");
  expect(wrapper.get('[data-diagnostic-field="frame_id"]').text()).toBe("Not recorded");
  const writeText = vi.fn(async () => {});
  vi.stubGlobal("navigator", { clipboard: { writeText } });
  await wrapper.get("#diagnostic-copy-identity").trigger("click");
  await flushPromises();
  expect(writeText).toHaveBeenCalledExactlyOnceWith(warning.identity);
  expect(JSON.stringify(model)).toBe(before);
});
test("filters only loaded rows and retains selected evidence outside the filter", async () => {
  const wrapper = setup(diagnosticFixture(), { ...initialSelection(), row: "a".repeat(64) });
  await wrapper.get("#diagnostics-filter").setValue("not-here");
  await wrapper.get("#diagnostics-filter-form").trigger("submit");
  await wrapper.setProps({ selection: wrapper.emitted("select")![0][0] as DiagnosticSelection });
  expect(wrapper.findAll("#diagnostics-rows li")).toHaveLength(0);
  expect(wrapper.get("#diagnostics-empty").text()).toContain("No loaded rows match");
  expect(wrapper.find("#diagnostics-outside-filter").exists()).toBe(true);
  expect(wrapper.get("#diagnostic-identity").element).toHaveProperty("value", "dashboard");
  await wrapper.get("#diagnostics-clear-filter").trigger("click");
  expect(wrapper.emitted("select")![1][0]).toEqual({ ...initialSelection(), row: "a".repeat(64) });
  await wrapper.setProps({ selection: initialSelection() });
  expect(wrapper.get("#diagnostics-filter").element).toHaveProperty("value", "");
});
test("rejects oversized filter submissions and searches scalar zero and false", async () => {
  const wrapper = setup();
  await wrapper.get("#diagnostics-filter").setValue("é".repeat(129));
  await wrapper.get("#diagnostics-filter-form").trigger("submit");
  expect(wrapper.emitted("select")).toBeUndefined();
  expect(wrapper.get("#diagnostics-filter").attributes("aria-invalid")).toBe("true");
  expect(wrapper.find("#diagnostics-filter-error").exists()).toBe(true);
  for (const search of [" DASHBOARD ", "false", "0", "initial"])
    expect(matchingRows(diagnosticFixture().collections[0].rows, search)).toHaveLength(1);
});
test("does not silently substitute a different row when a selection disappears", async () => {
  const wrapper = setup(diagnosticFixture(), { ...initialSelection(), row: "b".repeat(64) });
  expect(wrapper.find("#diagnostics-missing-selection").exists()).toBe(true);
  expect(wrapper.find("#diagnostic-identity").exists()).toBe(false);
  await wrapper.setProps({ selection: { ...initialSelection(), row: "a".repeat(64) } });
  expect(wrapper.find("#diagnostic-identity").exists()).toBe(true);
  const next = diagnosticFixture();
  next.collections[0].rows = [];
  await wrapper.setProps({ model: next });
  expect(wrapper.find("#diagnostics-missing-selection").exists()).toBe(true);
  expect(wrapper.find("#diagnostic-copy-identity").exists()).toBe(false);
});
test("distinguishes unavailable, empty, limited and process-local evidence", async () => {
  const model = diagnosticFixture();
  model.collections[0].limited = true;
  model.collections[1] = {
    id: "requests",
    state: "unavailable",
    source: null,
    limited: false,
    rows: [],
  };
  model.collections[5].source = "process_local";
  const wrapper = setup(model);
  expect(wrapper.find("#diagnostics-limited").exists()).toBe(true);
  await wrapper.setProps({ selection: { collection: "requests", row: null, filter: "" } });
  expect(wrapper.find("#diagnostics-unavailable").exists()).toBe(true);
  expect(wrapper.find("#diagnostics-empty").exists()).toBe(false);
  await wrapper.setProps({ selection: { collection: "refresh", row: null, filter: "" } });
  expect(wrapper.get("#diagnostics-provenance").text()).toBe("Process-local decision history");
  expect(wrapper.find("#diagnostics-local-warning").exists()).toBe(true);
  expect(wrapper.get("#diagnostics-empty").text()).toContain("No rows were recorded");
  await wrapper.setProps({ selection: { collection: "invalidation", row: null, filter: "" } });
  expect(wrapper.get("#diagnostics-provenance").text()).toBe("Durable decision history");
  expect(wrapper.find("#diagnostics-local-warning").exists()).toBe(false);
});
test("escapes allowed text, preserves exact identity and keeps DOM IDs unique", () => {
  const model = diagnosticFixture();
  model.name = "<img src=x onerror=alert(1)>";
  model.collections[0].rows[0].identity = "<script>alert(1)</script>";
  const wrapper = setup(model, { ...initialSelection(), row: "a".repeat(64) });
  expect(wrapper.find("img, script").exists()).toBe(false);
  expect(wrapper.get("h1").text()).toBe(model.name);
  const ids = wrapper.findAll("[id]").map((node) => node.attributes("id"));
  expect(new Set(ids).size).toBe(ids.length);
  expect(wrapper.get("#diagnostic-identity").element).toHaveProperty(
    "value",
    model.collections[0].rows[0].identity,
  );
});
test("copies literal diagnostic identity, never a URL, and reports failure honestly", async () => {
  const writeText = vi.fn(async () => {});
  vi.stubGlobal("navigator", { clipboard: { writeText } });
  const wrapper = setup(diagnosticFixture(), { ...initialSelection(), row: "a".repeat(64) });
  await wrapper.get("#diagnostic-copy-identity").trigger("click");
  await flushPromises();
  expect(writeText).toHaveBeenCalledExactlyOnceWith("dashboard");
  expect(wrapper.get("#diagnostic-copy-feedback").text()).toBe("Diagnostic identity copied.");
  writeText.mockRejectedValueOnce(Error("Denied"));
  await wrapper.get("#diagnostic-copy-identity").trigger("click");
  await flushPromises();
  expect(wrapper.get("#diagnostic-copy-feedback").text()).toContain("copy it manually");
  expect(wrapper.get("#diagnostic-identity").attributes("readonly")).toBeDefined();
});
test("late clipboard responses cannot claim a different selected identity was copied", async () => {
  let resolve!: () => void;
  vi.stubGlobal("navigator", {
    clipboard: {
      writeText: vi.fn(
        () =>
          new Promise<void>((r) => {
            resolve = r;
          }),
      ),
    },
  });
  const wrapper = mount(DiagnosticIdentity, { props: { identity: "first" } });
  wrappers.push(wrapper);
  await wrapper.get("#diagnostic-copy-identity").trigger("click");
  expect(wrapper.get("#diagnostic-copy-identity").attributes("disabled")).toBeDefined();
  await wrapper.setProps({ identity: "second" });
  resolve();
  await flushPromises();
  expect(wrapper.get("#diagnostic-copy-feedback").text()).toBe("");
  expect(wrapper.get("#diagnostic-copy-identity").attributes("disabled")).toBeUndefined();
});
