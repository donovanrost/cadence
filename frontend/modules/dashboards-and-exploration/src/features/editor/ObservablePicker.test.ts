import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import ObservablePicker from "./ObservablePicker.vue";
import { widgetDefaults } from "./contracts";
import { editorContext } from "./fixtures.test-support";
import { readObservableChoices } from "./validation";
const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
});
function choices(query = "", options = ["HK.voltage", "HK.current"]) {
  return {
    version: 2,
    organization_id: editorContext.organizationId,
    mission_id: editorContext.missionId,
    dashboard_id: editorContext.resourceId,
    document_version: 1,
    staging_revision: 0,
    query,
    options: options.map((value) => ({
      value,
      label: value,
      description: "Active telemetry · Unit: V",
    })),
    more: false,
  };
}
function render(
  execute = vi.fn(async (): Promise<unknown> => ({ status: "ok", choices: choices() })),
) {
  const app = mount(ObservablePicker, {
    props: {
      modelValue: "",
      fields: { ...widgetDefaults },
      context: editorContext,
      documentVersion: 1,
      stagingRevision: 0,
      port: { execute, navigate() {} },
      disabled: false,
    },
  });
  apps.push(app);
  return { app, execute };
}
test("search is explicit, read only, resource/version bound and separate from selection", async () => {
  const { app, execute } = render();
  expect(execute).not.toHaveBeenCalled();
  await app.get("#editor-observable-search").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("search_observables", {
    query: "",
    fields: widgetDefaults,
    expected_version: 1,
    expected_revision: 0,
  });
  expect(app.emitted("update:modelValue")).toBeUndefined();
  await app.get('[data-add-observable="HK.voltage"]').trigger("click");
  expect(app.emitted("update:modelValue")).toEqual([["HK.voltage"]]);
  await app.setProps({ modelValue: "HK.voltage" });
  expect(app.get('[data-add-observable="HK.current"]').attributes("disabled")).toBeDefined();
  await app.get('[data-remove-observable="0"]').trigger("click");
  expect(app.emitted("update:modelValue")?.at(-1)).toEqual([""]);
});
test("late results cannot survive a new query, changed scope, disabled editor or unmount", async () => {
  for (const change of ["query", "scope", "revision", "disabled", "unmount"]) {
    let resolve!: (value: unknown) => void;
    const { app } = render(
      vi.fn(
        () =>
          new Promise((r) => {
            resolve = r;
          }),
      ),
    );
    await app.get("#editor-observable-search").trigger("click");
    if (change === "query") await app.get("#editor-observable-query").setValue("other");
    if (change === "scope")
      await app.setProps({ fields: { ...widgetDefaults, mode: "fixed", spacecraft_id: "other" } });
    if (change === "revision") await app.setProps({ stagingRevision: 1 });
    if (change === "disabled") await app.setProps({ disabled: true });
    if (change === "unmount") app.unmount();
    resolve({ status: "ok", choices: choices() });
    await flushPromises();
    expect(app.find("#editor-observable-results").exists()).toBe(false);
    expect(app.emitted("update:modelValue")).toBeUndefined();
  }
});
test("unavailable search preserves selected unknown IDs and permits explicit retry", async () => {
  const execute = vi
    .fn()
    .mockRejectedValueOnce(Error("offline"))
    .mockResolvedValue({ status: "ok", choices: choices() });
  const { app } = render(execute);
  await app.setProps({ modelValue: "RETIRED.point" });
  await app.get("#editor-observable-search").trigger("click");
  await flushPromises();
  expect(app.find("#editor-observable-error").exists()).toBe(true);
  expect(app.get('[aria-label="Selected observables"]').text()).toContain("RETIRED.point");
  await app.get("#editor-observable-search").trigger("click");
  await flushPromises();
  expect(app.find("#editor-observable-results").exists()).toBe(true);
  expect(app.emitted("update:modelValue")).toBeUndefined();
});
test("multi-select preserves order, blocks duplicates and respects the chart limit", async () => {
  const { app } = render();
  await app.setProps({
    fields: { ...widgetDefaults, type: "time_series" },
    modelValue: "A\nB\nC\nD\nE\nF\nG",
  });
  await app.get("#editor-observable-search").trigger("click");
  await flushPromises();
  await app.get('[data-add-observable="HK.current"]').trigger("click");
  const value = "A\nB\nC\nD\nE\nF\nG\nHK.current";
  expect(app.emitted("update:modelValue")?.at(-1)).toEqual([value]);
  await app.setProps({ modelValue: value });
  expect(app.get('[data-add-observable="HK.voltage"]').attributes("disabled")).toBeDefined();
  expect(app.get('[data-add-observable="HK.current"]').attributes("disabled")).toBeDefined();
});
test("malformed, foreign, stale, duplicate and over-limit DTOs are rejected", () => {
  for (const mutate of [
    (v: unknown) => (fixtureRecordAt(v).organization_id = "other"),
    (v: unknown) => (fixtureRecordAt(v).mission_id = "other"),
    (v: unknown) => (fixtureRecordAt(v).dashboard_id = "other"),
    (v: unknown) => (fixtureRecordAt(v).document_version = 2),
    (v: unknown) => (fixtureRecordAt(v).version = 1),
    (v: unknown) => (fixtureRecordAt(v).staging_revision = 1),
    (v: unknown) => delete fixtureRecordAt(v).staging_revision,
    (v: unknown) => (fixtureRecordAt(v).query = "other"),
    (v: unknown) => fixtureArrayAt(v, "options").push(fixtureArrayAt(v, "options")[0]),
    (v: unknown) =>
      (fixtureRecordAt(v).options = Array.from(
        { length: 51 },
        () => fixtureArrayAt(v, "options")[0],
      )),
    (v: unknown) => (fixtureRecordAt(v, "options", 0).expression = "private"),
    (v: unknown) => (fixtureRecordAt(v).more = "false"),
    (v: unknown) => (fixtureRecordAt(v, "options", 0).value = "bad\nID"),
    (v: unknown) => (fixtureRecordAt(v, "options", 0).description = "x".repeat(4097)),
  ]) {
    const value = choices();
    mutate(value);
    expect(() => readObservableChoices(value, editorContext, 1, "", 0)).toThrow();
  }
});
