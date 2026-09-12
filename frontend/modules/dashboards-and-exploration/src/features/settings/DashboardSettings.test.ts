import {
  fixtureRecord,
  fixtureRecordAt,
  fixtureString,
  fixtureNumber,
  fixtureArrayAt,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import DashboardSettings from "./DashboardSettings.vue";
import SettingsLegacyRedirect from "./SettingsLegacyRedirect.vue";
import { settingsContext, settingsFixture } from "./fixtures.test-support";

const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.unstubAllGlobals();
});
function setup(
  override?: (event: string, input: unknown) => Promise<unknown>,
  initial = settingsFixture(),
) {
  let server = structuredClone(initial);
  const confirm = vi.fn(() => true);
  vi.stubGlobal("confirm", confirm);
  let guard = () => true;
  const navigated: string[] = [];
  const dispose = vi.fn();
  const execute = vi.fn(
    override ||
      (async (event: string, input: unknown) => {
        let receipt = null;
        if (event === "page_settings")
          server.model.query = {
            after_share:
              fixtureRecord(input).after_share === null
                ? null
                : fixtureString(fixtureRecord(input).after_share),
            after_snapshot:
              fixtureRecord(input).after_snapshot === null
                ? null
                : fixtureString(fixtureRecord(input).after_snapshot),
            after_deployment:
              fixtureRecord(input).after_deployment === null
                ? null
                : fixtureString(fixtureRecord(input).after_deployment),
          };
        else {
          server.sequence = fixtureNumber(fixtureRecord(input).sequence);
          server.phase = event === "reload_settings" ? "ready" : "review";
          if (event !== "reload_settings") {
            const command = fixtureRecordAt(input, "command");
            if (event === "save_settings") {
              Object.assign(server.model, {
                name: fixtureString(command.name).trim(),
                description: fixtureString(command.description).trim(),
                tags: fixtureArrayAt(command, "tags").map(fixtureString),
                defaults_json: fixtureString(command.defaults_json),
              });
              server.model.document_version++;
              server.model.revision++;
            }
            if (event === "archive_dashboard") {
              server.model.lifecycle = "archived";
              server.model.revision++;
            }
            receipt = {
              version: 1,
              dashboard_id: server.model.dashboard_id,
              event,
              document_version: server.model.document_version,
              revision: server.model.revision,
              resource_id:
                event === "revoke_share"
                  ? fixtureString(command.share_id)
                  : event === "create_share"
                    ? "created-share"
                    : event === "create_snapshot"
                      ? "created-snapshot"
                      : null,
            };
          }
        }
        return { status: "ok", receipt, state: structuredClone(server) };
      }),
  );
  const wrapper = mount(DashboardSettings, {
    props: {
      state: initial,
      context: settingsContext,
      port: {
        execute,
        navigate: (href: string) => {
          if (guard()) navigated.push(href);
        },
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return dispose;
        },
      },
    },
  });
  wrappers.push(wrapper);
  return { wrapper, execute, confirm, navigated, canLeave: () => guard(), dispose };
}
async function edit(w: Pick<ReturnType<typeof mount>, "get">, value = "New Power") {
  await w.get("#settings-name").setValue(value);
}

test("saves complete metadata with the observed version and remains consumed until explicit reload", async () => {
  const { wrapper, execute, canLeave } = setup();
  const input = wrapper.get("#settings-name").element;
  await edit(wrapper);
  expect(canLeave()).toBe(true);
  await wrapper.get("#settings-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("save_settings", {
    sequence: 1,
    command: {
      expected_version: 2,
      expected_revision: 3,
      name: "New Power",
      description: "",
      tags: ["power"],
      defaults_json: '{"extension":{"retained":true}}',
    },
  });
  expect(wrapper.get("#settings-name").element).toBe(input);
  expect(wrapper.find("#settings-dirty").exists()).toBe(false);
  expect(wrapper.get("#settings-outcome").text()).toContain("Saved as draft v3");
  await edit(wrapper, "Another edit");
  await wrapper.get("#settings-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
  await wrapper.get("#settings-reload").trigger("click");
  await flushPromises();
  expect(wrapper.get("#settings-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("Another edit");
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeUndefined();
});

test("metadata pagination preserves a dirty form, native controls and the write sequence", async () => {
  const state = settingsFixture();
  state.model.shares.rows = Array.from({ length: 25 }, (_, i) => ({
    ...required(state.model.shares.rows[0]),
    id: "share-" + i,
  }));
  state.model.shares.next = "share-24";
  const { wrapper, execute } = setup(undefined, state);
  await edit(wrapper);
  const input = wrapper.get("#settings-name").element;
  await wrapper.get("#settings-more-shares").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("page_settings", {
    after_share: "share-24",
    after_snapshot: null,
    after_deployment: null,
  });
  expect(wrapper.get("#settings-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("New Power");
  await wrapper.get("#settings-form").trigger("submit");
  await flushPromises();
  expect(fixtureRecord(required(execute.mock.calls[1])[1]).sequence).toBe(1);
});

test("uncertain writes stay locked through ordinary refresh and rejected sequences can recover", async () => {
  let calls = 0;
  const { wrapper, execute } = setup(async (_event, input) => {
    calls++;
    return calls === 1
      ? { status: "rejected", receipt: null, state: settingsFixture() }
      : {
          status: "ok",
          receipt: null,
          state: { ...settingsFixture(), sequence: fixtureNumber(fixtureRecord(input).sequence) },
        };
  });
  await edit(wrapper);
  await wrapper.get("#settings-form").trigger("submit");
  await flushPromises();
  await wrapper.setProps({ state: { ...settingsFixture(), phase: "ready" } });
  await wrapper.get("#settings-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
  await wrapper.get("#settings-reload").trigger("click");
  await flushPromises();
  expect(execute.mock.calls[1]).toEqual(["reload_settings", { sequence: 1, command: {} }]);
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeUndefined();
});

test("newer saved revisions retain local edits and require an explicit rebase or discard", async () => {
  const { wrapper, confirm } = setup();
  await edit(wrapper);
  const input = wrapper.get("#settings-name").element;
  const next = settingsFixture();
  next.model.name = "Changed elsewhere";
  next.model.document_version++;
  next.model.revision++;
  await wrapper.setProps({ state: next });
  expect(wrapper.get("#settings-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("New Power");
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#settings-current").text()).toContain("Changed elsewhere");
  confirm.mockReturnValue(false);
  await wrapper.get("#settings-rebase").trigger("click");
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeDefined();
  confirm.mockReturnValue(true);
  await wrapper.get("#settings-rebase").trigger("click");
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeUndefined();
  await wrapper.get("#settings-discard").trigger("click");
  expect((input as HTMLInputElement).value).toBe("Changed elsewhere");
  expect(wrapper.find("#settings-dirty").exists()).toBe(false);
});

test("shares use nullable or bounded expiration and snapshots use saved definitions", async () => {
  const { wrapper, execute } = setup();
  await edit(wrapper);
  await wrapper.get("#share-form").trigger("submit");
  await flushPromises();
  expect(execute.mock.calls[0]).toEqual([
    "create_share",
    {
      sequence: 1,
      command: {
        expected_version: 2,
        expected_revision: 3,
        data_visibility: "authorized_runtime_data",
        expires_in_hours: null,
      },
    },
  ]);
  expect(wrapper.find("#settings-dirty").exists()).toBe(true);
  expect(wrapper.get("#settings-created-link").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboard-shares/created-share",
  );
  await wrapper.get("#settings-reload").trigger("click");
  await flushPromises();
  await wrapper.get("#share-expiration").setValue("48");
  await wrapper.get("#share-form").trigger("submit");
  await flushPromises();
  expect(fixtureRecordAt(required(execute.mock.calls[2])[1], "command").expires_in_hours).toBe(48);
  await wrapper.get("#settings-reload").trigger("click");
  await flushPromises();
  await wrapper.get("#snapshot-form").trigger("submit");
  await flushPromises();
  expect(execute.mock.calls[4]).toEqual([
    "create_snapshot",
    {
      sequence: 5,
      command: {
        expected_version: 2,
        expected_revision: 3,
        data_visibility: "definition_only",
      },
    },
  ]);
  expect(wrapper.get("#settings-created-link").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboard-snapshots/created-snapshot",
  );
});

test("failed pagination retains the local draft and does not consume a write sequence", async () => {
  const initial = settingsFixture();
  initial.model.shares.rows = Array.from({ length: 25 }, (_, i) => ({
    ...required(initial.model.shares.rows[0]),
    id: "share-" + i,
  }));
  initial.model.shares.next = "share-24";
  const { wrapper, execute } = setup(async (event, input) => {
    if (event === "page_settings") throw Error("Transport unavailable");
    return {
      status: "invalid",
      receipt: null,
      state: { ...initial, sequence: fixtureNumber(fixtureRecord(input).sequence) },
    };
  }, initial);
  await edit(wrapper);
  const input = wrapper.get("#settings-name").element;
  await wrapper.get("#settings-more-shares").trigger("click");
  await flushPromises();
  expect(wrapper.get("#settings-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("New Power");
  expect(wrapper.findAll("#settings-shares > li")).toHaveLength(25);
  expect(wrapper.get("#settings-outcome").text()).toContain("page could not be loaded");
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeUndefined();
  await wrapper.get("#settings-form").trigger("submit");
  await flushPromises();
  expect(fixtureRecord(required(execute.mock.calls[1])[1]).sequence).toBe(1);
});

test("archive and revocation require confirmation and archive disables authoring", async () => {
  const { wrapper, execute, confirm } = setup();
  confirm.mockReturnValue(false);
  await wrapper.get("#settings-archive").trigger("click");
  await wrapper.get('[data-revoke-share="share-1"]').trigger("click");
  expect(execute).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  await wrapper.get('[data-revoke-share="share-1"]').trigger("click");
  await flushPromises();
  expect(fixtureRecordAt(required(execute.mock.calls[0])[1], "command").share_id).toBe("share-1");
  await wrapper.get("#settings-reload").trigger("click");
  await flushPromises();
  await wrapper.get("#settings-archive").trigger("click");
  await flushPromises();
  expect(wrapper.find("#settings-archived").exists()).toBe(true);
  expect(wrapper.get("#settings-form fieldset").attributes("disabled")).toBeDefined();
  expect(wrapper.find("#settings-archive").exists()).toBe(false);
});

test("pending writes are single-flight and dirty navigation/export require a choice", async () => {
  let resolve!: (v: unknown) => void;
  const { wrapper, execute, confirm, canLeave, navigated } = setup(
    () => new Promise((r) => (resolve = r)),
  );
  await edit(wrapper);
  confirm.mockReturnValue(false);
  expect(canLeave()).toBe(false);
  await wrapper.get("#settings-viewer").trigger("click");
  expect(navigated).toEqual([]);
  const exportEvent = new MouseEvent("click", { cancelable: true });
  wrapper.get("#settings-export").element.dispatchEvent(exportEvent);
  expect(exportEvent.defaultPrevented).toBe(true);
  const event = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
  await wrapper.get("#settings-form").trigger("submit");
  await wrapper.get("#settings-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
  expect(canLeave()).toBe(false);
  resolve({
    status: "invalid",
    receipt: null,
    state: { ...settingsFixture(), sequence: 1, phase: "ready" },
  });
  await flushPromises();
  expect(wrapper.find("#settings-dirty").exists()).toBe(true);
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeUndefined();
});

test("forged receipts cannot unlock the feature or mark local metadata saved", async () => {
  const { wrapper } = setup(async (_event, input) => ({
    status: "ok",
    receipt: {
      version: 1,
      dashboard_id: "foreign",
      event: "save_settings",
      document_version: 3,
      revision: 4,
      resource_id: null,
    },
    state: {
      ...settingsFixture(),
      sequence: fixtureNumber(fixtureRecord(input).sequence),
      phase: "review",
    },
  }));
  await edit(wrapper);
  await wrapper.get("#settings-form").trigger("submit");
  await flushPromises();
  expect(wrapper.find("#settings-dirty").exists()).toBe(true);
  expect(wrapper.get("#settings-save").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#settings-outcome").text()).toContain("could not be confirmed");
});

test("legacy delivery only links to the canonical host route and rejects malformed identities", async () => {
  const wrapper = mount(SettingsLegacyRedirect, {
    props: { mission_id: "mission-1", dashboard_id: "dashboard-1" },
  });
  wrappers.push(wrapper);
  expect(wrapper.get("#settings-open-workspace").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1/settings",
  );
  expect(wrapper.find("form").exists()).toBe(false);
  await wrapper.setProps({ dashboard_id: "../forged" });
  expect(wrapper.find("#settings-open-workspace").exists()).toBe(false);
});
