import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import InstallationManagementPage from "./InstallationManagementPage.vue";
import { installationSnapshot } from "./fixtures.test-support";
import { admitSnapshot } from "./validation";

let wrapper: VueWrapper | undefined;
const originalConfirm = window.confirm;
afterEach(() => {
  wrapper?.unmount();
  window.confirm = originalConfirm;
  vi.restoreAllMocks();
});

test.each(["mission", "spacecraft"] as const)(
  "the %s inventory preserves confirmations and emits only the application key",
  async (scope) => {
    const execute = vi.fn(async () => {});
    const confirmation = vi.fn(() => false);
    window.confirm = confirmation;
    wrapper = mount(InstallationManagementPage, {
      props: {
        scope,
        snapshot: installationSnapshot(scope),
        execute,
        refresh: vi.fn(async () => {}),
      },
    });
    const key = scope === "mission" ? "limits" : "telemetry_decom";
    await wrapper.get("#" + key + "-disable").trigger("click");
    expect(confirmation).toHaveBeenCalledOnce();
    expect(execute).not.toHaveBeenCalled();
    confirmation.mockReturnValue(true);
    await wrapper.get("#" + key + "-disable").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenLastCalledWith("disable", { key });
    await wrapper.get("#" + key + "-uninstall").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenLastCalledWith("uninstall", { key });
    await wrapper.get("#" + key + "-install").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenLastCalledWith("install", { key });
  },
);

test("pending actions disable duplicate clicks and failure leaves the inventory usable", async () => {
  let reject!: (error: Error) => void;
  const execute = vi.fn(
    () =>
      new Promise<void>((_resolve, no) => {
        reject = no;
      }),
  );
  wrapper = mount(InstallationManagementPage, {
    props: {
      scope: "mission",
      snapshot: installationSnapshot(),
      execute,
      refresh: vi.fn(async () => {}),
    },
  });
  await wrapper.get("#limits-install").trigger("click");
  expect(wrapper.get("#limits-install").attributes("disabled")).toBeDefined();
  await wrapper.get("#limits-install").trigger("click");
  expect(execute).toHaveBeenCalledOnce();
  reject(new Error("private diagnostic"));
  await flushPromises();
  expect(wrapper.get("#application-installation-action-error").text()).not.toContain(
    "private diagnostic",
  );
  expect(wrapper.get("#limits-install").attributes("disabled")).toBeUndefined();
  expect(wrapper.find("#mission-applications-list").exists()).toBe(true);
});

test("unsupported versions, wrong scopes and malformed nested actions are contained and can be retried", async () => {
  const refresh = vi.fn(async () => {});
  const snapshot = installationSnapshot();
  wrapper = mount(InstallationManagementPage, {
    props: {
      scope: "mission",
      snapshot: { ...snapshot, version: 2 },
      execute: vi.fn(async () => {}),
      refresh,
    },
  });
  expect(wrapper.find("#application-installation-unavailable").exists()).toBe(true);
  expect(wrapper.find("#limits-install").exists()).toBe(false);
  await wrapper.get("#application-installation-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  expect(admitSnapshot(snapshot, "spacecraft")).toBeNull();
  const bad = installationSnapshot();
  if (bad.scope !== "mission") throw new Error("fixture");
  bad.data.applications_component.props.applications[0]!.disable_action!.action_id = "uninstall";
  expect(admitSnapshot(bad, "mission")).toBeNull();
  await wrapper.setProps({ snapshot });
  expect(wrapper.find("#mission-applications-list").exists()).toBe(true);
});

test("missing profiles retain the identity handoff and nullable facts render safely", () => {
  const snapshot = installationSnapshot("spacecraft");
  if (snapshot.scope !== "spacecraft") throw new Error("fixture");
  snapshot.data.profile = {
    kind: "missing",
    id: "missing-profile",
    label: "Profile",
    title: "No profile selected",
    description: "Select a profile.",
    action: {
      label: "Select profile",
      path: "/missions/mission-a/spacecraft/spacecraft-a/identity",
    },
  };
  snapshot.data.applications[0]!.status.facts[0]!.value = null;
  wrapper = mount(InstallationManagementPage, {
    props: {
      scope: "spacecraft",
      snapshot,
      execute: vi.fn(async () => {}),
      refresh: vi.fn(async () => {}),
    },
  });
  expect(wrapper.get("#missing-profile a").attributes("href")).toBe(
    snapshot.data.profile.action.path,
  );
  expect(wrapper.get("#spacecraft-applications-list").text()).toContain("—");
  snapshot.data.header.actions.readiness.attrs.href = "javascript:alert(1)";
  expect(admitSnapshot(snapshot, "spacecraft")).toBeNull();
});
