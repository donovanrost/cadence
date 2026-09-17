import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import type { SettingsWriteResult } from "@cadence/plugin-sdk/settings";
import SettingsPage from "./SettingsPage.vue";
import { settingsSections } from "./contributions";
import { createSettingsDrafts } from "./drafts";
import { readSettingsPage, settingsDraftKey } from "./contracts";
import {
  settingsContext as context,
  settingsFixture,
  settingsValue,
} from "./fixtures.test-support";
let wrapper: VueWrapper | undefined;
afterEach(() => {
  wrapper?.unmount();
  wrapper = undefined;
});
function view() {
  if (!wrapper) throw Error("Missing settings view");
  return wrapper;
}
function button(label: string) {
  const match = view()
    .findAll("button")
    .find((item) => item.text() === label);
  if (!match) throw Error("Missing button: " + label);
  return match;
}
async function open(snapshot = settingsFixture()) {
  // Feature interactions begin after lazy code loading; the registry has its own lifecycle tests.
  await Promise.all(settingsSections.ids.map((id) => settingsSections.load(id)));
  const drafts = createSettingsDrafts();
  const execute = vi
    .fn<() => Promise<SettingsWriteResult>>()
    .mockResolvedValue({ status: "unconfirmed" });
  const refresh = vi.fn<() => Promise<void>>().mockResolvedValue();
  wrapper = mount(SettingsPage, {
    props: {
      snapshot,
      context,
      sectionId: "cadence.governance",
      drafts,
      execute,
      refresh,
      navigating: false,
    },
  });
  await vi.waitFor(() => expect(view().find('input[value="direct"]').exists()).toBe(true));
  return { drafts, execute, refresh };
}
test("saves an exact mission override through the admitted section", async () => {
  const { execute, drafts } = await open();
  const saved = {
    ...settingsValue(),
    token: "b".repeat(64),
    version: 1,
    saved: { approval_requirement: "direct" },
    effective: { approval_requirement: "direct" },
    source: "overridden",
  };
  execute.mockResolvedValue({ status: "saved", revisionId: "revision-1", snapshot: saved });
  await view().get('input[value="direct"]').setValue(true);
  await button("Save changes").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith({
    token: "settings-page-token",
    revisionToken: "a".repeat(64),
    document: { value: { approval_requirement: "direct" } },
  });
  expect(view().text()).toContain("Changes saved.");
  expect(drafts.hasUnsaved()).toBe(false);
});
test("live changes preserve edits and require reconciliation against the new token", async () => {
  const { execute } = await open();
  await view().get('input[value="direct"]').setValue(true);
  const latest = { ...settingsValue(), token: "b".repeat(64) };
  await view().setProps({ snapshot: settingsFixture(context, "cadence.governance", latest) });
  expect(view().text()).toContain("Saved settings changed");
  expect(button("Save changes").attributes("disabled")).toBeDefined();
  await button("Keep my changes").trigger("click");
  await button("Save changes").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith(expect.objectContaining({ revisionToken: latest.token }));
});
test("enforcement preserves a draft while disabling both editing and rebasing", async () => {
  const { drafts } = await open();
  await view().get('input[value="direct"]').setValue(true);
  const latest = {
    ...settingsValue(),
    token: "b".repeat(64),
    source: "enforced",
    allow_override: false,
  };
  await view().setProps({ snapshot: settingsFixture(context, "cadence.governance", latest) });
  expect(view().get("fieldset").attributes("disabled")).toBeDefined();
  expect(button("Keep my changes").attributes("disabled")).toBeDefined();
  expect(button("Save changes").attributes("disabled")).toBeDefined();
  expect(drafts.dirty(settingsDraftKey(context, "cadence.governance"))).toBe(true);
});
test("uncertain writes require a successful read before another save", async () => {
  const { execute, refresh } = await open();
  await view().get('input[value="direct"]').setValue(true);
  await button("Save changes").trigger("click");
  await flushPromises();
  expect(button("Save changes").attributes("disabled")).toBeDefined();
  refresh.mockRejectedValueOnce(Error("offline"));
  await button("Check saved values").trigger("click");
  await flushPromises();
  expect(button("Save changes").attributes("disabled")).toBeDefined();
  await button("Check saved values").trigger("click");
  await flushPromises();
  expect(button("Save changes").attributes("disabled")).toBeUndefined();
  expect(execute).toHaveBeenCalledTimes(1);
});
test("returning after an uncertain save recognizes the already persisted values", async () => {
  const { drafts } = await open();
  await view().get('input[value="direct"]').setValue(true);
  view().unmount();
  const saved = {
    ...settingsValue(),
    token: "b".repeat(64),
    version: 1,
    saved: { approval_requirement: "direct" },
    effective: { approval_requirement: "direct" },
    source: "overridden",
  };
  wrapper = mount(SettingsPage, {
    props: {
      snapshot: settingsFixture(context, "cadence.governance", saved),
      context,
      sectionId: "cadence.governance",
      drafts,
      execute: async () => ({ status: "unconfirmed" }),
      refresh: async () => {},
      navigating: false,
    },
  });
  await flushPromises();
  expect(view().text()).not.toContain("Saved settings changed");
  expect(drafts.hasUnsaved()).toBe(false);
});
test("a failed application section leaves navigation and the Governance draft available", async () => {
  const { drafts } = await open();
  await view().get('input[value="direct"]').setValue(true);
  await view().setProps({
    sectionId: "commanding.defaults",
    snapshot: settingsFixture(context, "commanding.defaults", {}),
  });
  await vi.waitFor(() => expect(view().text()).toContain("Commanding settings are unavailable"));
  expect(view().find('nav[aria-label="Settings sections"] a').exists()).toBe(true);
  await view().setProps({ sectionId: "cadence.governance", snapshot: settingsFixture() });
  await flushPromises();
  expect(button("Save changes").exists()).toBe(true);
  expect(drafts.hasUnsaved()).toBe(true);
});
test("the settings reader rejects scope substitution and duplicate contribution identities", () => {
  const page = settingsFixture();
  expect(() =>
    readSettingsPage(
      { ...page, context: { ...page.context, mission_id: "foreign" } },
      context,
      "cadence.governance",
    ),
  ).toThrow();
  expect(() =>
    readSettingsPage(
      { ...page, data: { ...page.data, sections: [...page.data.sections, ...page.data.sections] } },
      context,
      "cadence.governance",
    ),
  ).toThrow();
});
