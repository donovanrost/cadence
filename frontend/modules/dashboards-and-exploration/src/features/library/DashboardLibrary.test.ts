import { required } from "../../../../../test-support/required";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import DashboardLibrary from "./DashboardLibrary.vue";
import { readLibrary } from "./validation";
import { parseWidgetJson, widgetExample } from "./widget-json";
import { libraryContribution } from "./contribution";
import { libraryContext, libraryFixture } from "./fixtures.test-support";
import type { LibraryReceipt, LibraryState } from "./contracts";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.unstubAllGlobals();
});
function setup(
  state = libraryFixture(),
  execute = vi.fn(async (): Promise<unknown> => {
    throw Error("Lost response");
  }),
) {
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  let guard = () => true;
  const dispose = vi.fn(),
    navigate = vi.fn((_: string) => guard());
  const wrapper = mount(DashboardLibrary, {
    props: {
      state,
      context: libraryContext,
      port: {
        execute,
        navigate,
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return dispose;
        },
      },
    },
  });
  wrappers.push(wrapper);
  return { wrapper, execute, navigate, dispose, canLeave: () => guard() };
}
const receipt = (event: LibraryReceipt["event"]): LibraryReceipt => ({
  version: 1,
  event,
  item_id: "library-1",
  library_version: event === "add_version" ? 3 : 1,
  dashboard_id: event === "add_to_draft" ? "dashboard-1" : null,
  document_version: event === "add_to_draft" ? 4 : null,
  placement_id: event === "add_to_draft" ? "pin-new" : null,
});
const reply = (
  state: LibraryState,
  receipt: LibraryReceipt | null = null,
  status = "ok",
  code: string | null = null,
) => ({ state, receipt, status, code });
test("admits semantic library DTOs, scopes and finite pinned histories", () => {
  expect(libraryContribution.read(libraryFixture(), libraryContext).state).toEqual(
    libraryFixture(),
  );
  expect(readLibrary(libraryFixture(false), libraryContext)).toEqual(libraryFixture(false));
  for (const mutate of [
    (s: unknown) => (fixtureRecordAt(s, "model").version = 2),
    (s: unknown) => (fixtureRecordAt(s, "model").mission_id = "foreign"),
    (s: unknown) => (fixtureRecordAt(s, "model", "selected", "item").id = "foreign"),
    (s: unknown) => (fixtureRecordAt(s, "model", "target").version = null),
    (s: unknown) => (fixtureRecordAt(s, "model", "selected").version = 2),
    (s: unknown) => fixtureArrayAt(s, "model", "selected", "versions").reverse(),
    (s: unknown) =>
      (fixtureRecordAt(s, "model").items = Array.from(
        { length: 26 },
        () => fixtureArrayAt(s, "model", "items")[0],
      )),
    (s: unknown) =>
      (fixtureRecordAt(s, "model", "selected", "consumers", "rows", 0, "pins", 0).version = 0),
    (s: unknown) => (fixtureRecordAt(s, "model", "selected", "consumers", "rows", 0).document = {}),
  ]) {
    const bad = libraryFixture();
    mutate(bad);
    expect(() => readLibrary(bad, libraryContext)).toThrow();
  }
  expect(() =>
    readLibrary(libraryFixture(), { ...libraryContext, resourceId: "unexpected" }),
  ).toThrow();
});
test("invalid JSON is local and consumes no sequence", async () => {
  const { wrapper, execute } = setup();
  await wrapper.get("#library-widget-json").setValue("{");
  await wrapper.get("#library-definition-form").trigger("submit");
  expect(execute).not.toHaveBeenCalled();
  expect(wrapper.get("#library-json-error").text()).toContain("valid widget JSON");
  for (const value of [
    "[]",
    "{}",
    " ".repeat(32769),
    JSON.stringify({
      widget_type_id: "type",
      options: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [String(i), i])),
    }),
  ])
    expect(() => parseWidgetJson(value)).toThrow();
});
test("widget JSON admits omitted defaults but rejects malformed explicit fields locally", async () => {
  for (const value of [
    { widget_type_id: "type" },
    { widget_type_id: "type", title: null, binding: {}, options: {} },
  ])
    expect(parseWidgetJson(JSON.stringify(value))).toEqual(value);

  const { wrapper, execute } = setup();
  for (const fields of [
    { binding: null },
    { options: null },
    { title: {} },
    { title: 42 },
    { widget_type_id: "x".repeat(257) },
    { widget_type_id: "é".repeat(129) },
    { widget_type_id: "bad\nidentifier" },
    { widget_type_version: Number.MAX_SAFE_INTEGER },
  ]) {
    await wrapper
      .get("#library-widget-json")
      .setValue(JSON.stringify({ widget_type_id: "type", ...fields }));
    await wrapper.get("#library-definition-form").trigger("submit");
    expect(wrapper.find("#library-json-error").exists()).toBe(true);
    expect(execute).not.toHaveBeenCalled();
  }
});
test("new versions use the observed latest while existing consumers remain pinned", async () => {
  const next = libraryFixture();
  next.sequence = 1;
  required(next.model.selected).item.latest_version = 3;
  const { wrapper, execute, canLeave } = setup(
    libraryFixture(),
    vi.fn(async () => reply(next, receipt("add_version"))),
  );
  await wrapper.get("#library-summary").setValue("Updated options");
  await wrapper.get("#library-definition-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("add_version", {
    sequence: 1,
    command: {
      item_id: "library-1",
      expected_version: 2,
      widget_json: widgetExample,
      change_summary: "Updated options",
    },
  });
  expect(wrapper.get("#library-outcome").text()).toContain("Existing consumers keep");
  expect(wrapper.get("#library-consumers").text()).toContain("pinned v1");
  expect(canLeave()).toBe(true);
});
test("creation acknowledges an exact receipt without discarding unrelated form data", async () => {
  const next = libraryFixture(false);
  next.sequence = 1;
  const { wrapper, execute } = setup(
    libraryFixture(false),
    vi.fn(async () => reply(next, receipt("create_item"))),
  );
  await wrapper.get("#library-name").setValue("New widget");
  await wrapper.get("#library-definition-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("create_item", {
    sequence: 1,
    command: {
      name: "New widget",
      description: "",
      change_summary: "",
      widget_json: widgetExample,
    },
  });
  expect(wrapper.get("#library-saved-item").attributes("href")).toContain(
    "item_id=library-1&version=1",
  );
  expect(wrapper.get("#library-draft-state").text()).toBe("Definition unchanged");
});
test("pinning is confirmed, version-bound and does not clear an unsaved library definition", async () => {
  const next = libraryFixture();
  next.sequence = 1;
  required(next.model.target).version = 4;
  const { wrapper, execute } = setup(
    libraryFixture(),
    vi.fn(async () => reply(next, receipt("add_to_draft"))),
  );
  await wrapper.get("#library-summary").setValue("Unsaved work");
  await wrapper.get("#library-add-to-draft").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  vi.mocked(window.confirm).mockReturnValue(true);
  await wrapper.get("#library-add-to-draft").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("add_to_draft", {
    sequence: 1,
    command: { item_id: "library-1", version: 1, dashboard_id: "dashboard-1", expected_version: 3 },
  });
  expect(wrapper.get("#library-draft-state").text()).toBe("Unsaved definition");
  expect(wrapper.get("#library-saved-dashboard").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1/edit",
  );
});
test("refresh preserves native draft identity and a changed library version requires review", async () => {
  const { wrapper } = setup();
  const textarea = wrapper.get("#library-widget-json").element;
  await wrapper.get("#library-summary").setValue("Retained");
  await wrapper.setProps({ state: libraryFixture() });
  expect(wrapper.get("#library-widget-json").element).toBe(textarea);
  const changed = libraryFixture();
  required(changed.model.selected).item.latest_version = 3;
  await wrapper.setProps({ state: changed });
  expect(wrapper.get("#library-definition-form fieldset").attributes("disabled")).toBeDefined();
  expect((wrapper.get("#library-summary").element as HTMLInputElement).value).toBe("Retained");
  expect(wrapper.get("#library-outcome").text()).toContain("changed while you were editing");
});
test("declined navigation keeps the target selector and dirty definition on the admitted identity", async () => {
  const { wrapper, canLeave } = setup();
  await wrapper.get("#library-summary").setValue("Unsaved");
  expect(canLeave()).toBe(false);
  await wrapper.get("#library-target").setValue("dashboard-2");
  expect((wrapper.get("#library-target").element as HTMLSelectElement).value).toBe("dashboard-1");
  const event = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
});
test("unknown receipts stay locked through refresh until explicit reload", async () => {
  for (const response of [
    new Error("Lost"),
    reply({ ...libraryFixture(), sequence: 1 }, null, "conflict"),
    reply({ ...libraryFixture(), sequence: 1 }, { ...receipt("add_version"), library_version: 9 }),
  ]) {
    const execute = vi.fn(async () => {
      if (response instanceof Error) throw response;
      return response;
    });
    const { wrapper } = setup(libraryFixture(), execute);
    await wrapper.get("#library-definition-form").trigger("submit");
    await flushPromises();
    await wrapper.setProps({ state: { ...libraryFixture(), sequence: 1 } });
    expect(wrapper.get("#library-definition-form fieldset").attributes("disabled")).toBeDefined();
    execute.mockResolvedValue(reply({ ...libraryFixture(), sequence: 2 }));
    await wrapper.get("#library-reload").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenLastCalledWith("reload_library", { sequence: 2, command: {} });
    expect(wrapper.get("#library-definition-form fieldset").attributes("disabled")).toBeUndefined();
  }
});
test("known validation rejection retains editable JSON and pending requests guard duplicate effects", async () => {
  let resolve!: (value: unknown) => void;
  const { wrapper, execute, canLeave } = setup(
    libraryFixture(),
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  await wrapper.get("#library-summary").setValue("Retained");
  await wrapper.get("#library-definition-form").trigger("submit");
  expect(canLeave()).toBe(false);
  await wrapper.get("#library-definition-form").trigger("submit");
  expect(execute).toHaveBeenCalledOnce();
  resolve(reply({ ...libraryFixture(), sequence: 1 }, null, "invalid", "invalid_widget"));
  await flushPromises();
  expect(wrapper.get("#library-definition-form fieldset").attributes("disabled")).toBeUndefined();
  expect((wrapper.get("#library-summary").element as HTMLInputElement).value).toBe("Retained");
});
