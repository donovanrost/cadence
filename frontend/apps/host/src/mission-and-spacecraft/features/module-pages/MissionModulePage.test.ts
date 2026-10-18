import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import MissionModulePage from "./MissionModulePage.vue";
import { admitMissionPages } from "./mission-contributions";
import { loadedMissionPages as missionModulePages } from "../../../module-pages.test-support";
import { missionSnapshots } from "./mission-pages.test-support";
import { transportFormPayload } from "../../../../../../modules/communications/src/features/transports/fixtures.test-support";
import MissionTransportCreation from "../../../../../../modules/communications/src/features/transports/MissionTransportCreation.vue";

function formSnapshot() {
  return {
    id: "comms.transport-new",
    slot: "mission.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: { organizationId: "org-1", missionId: "mission-1" },
    data: {
      phase: "editing",
      model: {
        navigation: { fallback_href: "/missions/mission-1/comms/transports/new", breadcrumbs: [] },
        data: transportFormPayload(),
      },
    },
  };
}
test("action contributions require a valid token and both host ports", () => {
  const valid = formSnapshot();
  for (const overrides of [
    { snapshot: { ...valid, token: undefined } },
    { snapshot: { ...valid, token: "-".repeat(36) } },
    { execute: undefined },
    { navigate: undefined },
  ]) {
    const { execute, navigate, ...pageProps } = {
      contributionId: valid.id,
      snapshot: valid,
      context: valid.context,
      refresh: vi.fn(),
      execute: vi.fn(),
      navigate: vi.fn(),
      ...overrides,
    };
    const wrapper = mount(MissionModulePage, {
      props: { ...pageProps, ...(execute ? { execute } : {}), ...(navigate ? { navigate } : {}) },
    });
    expect(wrapper.find("#mission-module-unavailable").exists()).toBe(true);
    wrapper.unmount();
  }
});
test("mission ports admit only declared actions and reject responses after instance replacement", async () => {
  const valid = formSnapshot();
  let finish!: (value: unknown) => void;
  const execute = vi.fn().mockReturnValue(
    new Promise((resolve) => {
      finish = resolve;
    }),
  );
  const navigate = vi.fn();
  const wrapper = mount(MissionModulePage, {
    props: {
      contributionId: valid.id,
      snapshot: valid,
      context: valid.context,
      refresh: vi.fn(),
      execute,
      navigate,
    },
  });
  const port: MissionPagePort = wrapper.getComponent(MissionTransportCreation).props("port");
  try {
    await expect(port.execute("delete", {})).rejects.toThrow();
    expect(execute).not.toHaveBeenCalled();
    const pending = port.execute("validate", { transport: { display_name: "Draft" } });
    expect(execute).toHaveBeenCalledWith({
      id: valid.id,
      token: valid.token,
      event: "validate",
      input: { transport: { display_name: "Draft" } },
    });
    await wrapper.setProps({
      snapshot: { ...valid, token: "22222222-2222-4222-8222-222222222222" },
    });
    finish({ status: "ok" });
    await expect(pending).rejects.toThrow("Inactive mission page response");
    port.navigate("/missions/mission-1");
    expect(navigate).not.toHaveBeenCalled();
    await expect(port.execute("save", {})).rejects.toThrow();
    expect(execute).toHaveBeenCalledTimes(1);
  } finally {
    wrapper.unmount();
  }
});
test("refresh, route identity changes and unmount invalidate retained action ports", async () => {
  for (const update of [
    { refreshing: true },
    { contributionId: "unknown" },
    { context: { organizationId: "other", missionId: "mission-1" } },
  ]) {
    const valid = formSnapshot(),
      execute = vi.fn(),
      navigate = vi.fn();
    const wrapper = mount(MissionModulePage, {
      props: {
        contributionId: valid.id,
        snapshot: valid,
        context: valid.context,
        refresh: vi.fn(),
        execute,
        navigate,
      },
    });
    const port: MissionPagePort = wrapper.getComponent(MissionTransportCreation).props("port");
    await wrapper.setProps(update);
    await expect(port.execute("validate", {})).rejects.toThrow();
    port.navigate("/missions/mission-1");
    expect(execute).not.toHaveBeenCalled();
    expect(navigate).not.toHaveBeenCalled();
    wrapper.unmount();
    await expect(port.execute("save", {})).rejects.toThrow();
  }
});

test("all eight mission contributions render their existing feature components", () => {
  for (const snapshot of missionSnapshots()) {
    const registration = required(missionModulePages[snapshot.id]);
    const wrapper = mount(MissionModulePage, {
      props: {
        contributionId: snapshot.id,
        snapshot,
        context: snapshot.context,
        refresh: vi.fn(),
      },
    });
    expect(wrapper.find("#mission-module-unavailable").exists(), snapshot.id).toBe(false);
    expect(wrapper.findComponent(registration.component).exists(), snapshot.id).toBe(true);
    wrapper.unmount();
  }
});
test("admission binds identity, version, slot, mission and resource before rendering", async () => {
  for (const valid of missionSnapshots()) {
    const wrapper = mount(MissionModulePage, {
      props: {
        contributionId: valid.id,
        snapshot: valid,
        context: valid.context,
        refresh: vi.fn(),
      },
    });
    for (const snapshot of [
      null,
      { ...valid, id: "unknown" },
      { ...valid, version: 2 },
      { ...valid, slot: "organization.page" },
      { ...valid, status: "unavailable" },
      ...["organizationId", "missionId", "resourceId"].map((key) => ({
        ...valid,
        context: { ...valid.context, [key]: "foreign" },
      })),
      { ...valid, data: {} },
    ]) {
      await wrapper.setProps({ snapshot });
      expect(wrapper.find("#mission-module-unavailable").exists(), valid.id).toBe(true);
    }
    await wrapper.setProps({ snapshot: valid, contributionId: "__proto__" });
    expect(wrapper.find("#mission-module-unavailable").exists()).toBe(true);
    wrapper.unmount();
  }
});
test("detail features reject another resource even when the envelope claims the current resource", () => {
  for (const snapshot of missionSnapshots().filter((item) => item.context.resourceId)) {
    expect(() =>
      required(missionModulePages[snapshot.id]).read(snapshot.data, {
        ...snapshot.context,
        resourceId: "another-resource",
      }),
    ).toThrow();
  }
});
test("unavailable reads retry and renderer failures recover with a fresh snapshot", async () => {
  const valid = required(missionSnapshots()[2]);
  const refresh = vi.fn().mockResolvedValue(undefined);
  const component = required(missionModulePages[valid.id]).component;
  const setup = vi
    .spyOn(component as { setup: (...args: unknown[]) => unknown }, "setup")
    .mockImplementation(() => {
      throw new Error("private renderer failure");
    });
  const wrapper = mount(MissionModulePage, {
    props: {
      contributionId: valid.id,
      snapshot: valid,
      context: valid.context,
      refresh,
    },
  });
  try {
    await wrapper.vm.$nextTick();
    expect(wrapper.find("#mission-module-unavailable").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private renderer failure");
    await wrapper.get("#mission-module-retry").trigger("click");
    expect(refresh).toHaveBeenCalledTimes(1);
    setup.mockRestore();
    await wrapper.setProps({ snapshot: missionSnapshots()[2] });
    expect(wrapper.find("#mission-module-unavailable").exists()).toBe(false);
    expect(wrapper.get("#comms-transports-directory-search").attributes("method")).toBe("get");
    expect(wrapper.get("#comms-transports-directory-next").attributes("href")).toContain("page=2");
  } finally {
    setup.mockRestore();
    wrapper.unmount();
  }
});
test("registration admits only unique supported compiled contributions", () => {
  const registration = required(missionModulePages["comms.transports"]);
  expect(Object.keys(missionModulePages)).toHaveLength(15);
  expect(() => admitMissionPages([registration, registration])).toThrow();
  expect(() => admitMissionPages([{ ...registration, version: 2 } as never])).toThrow();
  expect(() =>
    admitMissionPages([{ ...registration, slot: "spacecraft.page" } as never]),
  ).toThrow();
});
