import { containing } from "../../../../../test-support/matchers";
import { mount, flushPromises } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test, vi } from "vite-plus/test";
import Creation from "./MissionProviderCreation.vue";
import Detail from "./MissionProviderDetail.vue";
import { missionPages } from "./mission.contribution";
import { providerNewSurface, providerDetailSurface } from "./surface-fixtures.test-support";
const context = { organizationId: "org-1", missionId: "mission-1" };
const creation = () => ({ model: providerNewSurface(), sequence: 0, phase: "editing" });
const detail = (version = 1, sequence = 0, phase = "editing") => ({
  model: providerDetailSurface(version),
  sequence,
  phase,
});
const detailContext = { ...context, resourceId: "provider-1" };
const receipt = (version = 2) => ({
  status: "ok",
  sequence: 1,
  data: { result: { provider_id: "provider-1", version, display_name: "Simulator" } },
});
test("provider creation preserves its draft on host refresh and navigates after one confirmed effect", async () => {
  const port = { execute: vi.fn().mockResolvedValue(receipt()), navigate: vi.fn() };
  const wrapper = mount(Creation, {
    props: { ...missionPages[1].read(creation(), context), port } as never,
  });
  try {
    const input = wrapper.get("#provider_display_name").element;
    await wrapper.get("#provider_display_name").setValue("Host draft");
    await wrapper.setProps(missionPages[1].read(creation(), context));
    expect(wrapper.get("#provider_display_name").element).toBe(input);
    expect(input).toHaveProperty("value", "Host draft");
    await wrapper.get("#mission-provider-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("create-provider", {
      sequence: 1,
      provider: containing({
        display_name: "Host draft",
        provider_account_version: "3",
        provider_account_grant_version: "1",
      }),
    });
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith(
      "/missions/mission-1/comms/providers/provider-1",
    );
    await wrapper.get("#mission-provider-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledTimes(1);
  } finally {
    wrapper.unmount();
  }
});
test("unknown creation keeps fields locked across host refresh", async () => {
  const port = { execute: vi.fn().mockRejectedValue(new Error("private")), navigate: vi.fn() };
  const wrapper = mount(Creation, {
    props: { ...missionPages[1].read(creation(), context), port } as never,
  });
  try {
    await wrapper.get("#mission-provider-form").trigger("submit");
    await flushPromises();
    await wrapper.setProps(
      missionPages[1].read({ ...creation(), sequence: 1, phase: "submitted" }, context),
    );
    expect(wrapper.get("fieldset.contents").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#comms-setup-outcome").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private");
    await wrapper.get("#mission-provider-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledTimes(1);
  } finally {
    wrapper.unmount();
  }
});
test("provider actions send observed versions and consume an ordered sequence before querying fresh state", async () => {
  const port = {
    execute: vi
      .fn()
      .mockResolvedValueOnce(receipt())
      .mockResolvedValueOnce({ status: "ok", sequence: 1, data: detail(3, 1) })
      .mockResolvedValueOnce({ status: "rejected", sequence: 1 }),
    navigate: vi.fn(),
  };
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/comms/providers/:provider_id").stage(Detail),
    {
      props: { ...missionPages[2].read(detail(), detailContext), port } as never,
    },
  );
  try {
    await wrapper.get("#sync-provider-button").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenNthCalledWith(1, "sync-provider", {
      provider_id: "provider-1",
      expected_provider_version: 1,
      sequence: 1,
    });
    expect(port.execute).toHaveBeenNthCalledWith(2, "refresh", {});
    expect(wrapper.find("#version-3").exists()).toBe(true);
    await wrapper.get("#validate-provider-button").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenNthCalledWith(3, "validate-provider", {
      provider_id: "provider-1",
      expected_provider_version: 3,
      sequence: 2,
    });
  } finally {
    wrapper.unmount();
  }
});
test("unknown detail effects stay locked after query and host refresh", async () => {
  const port = {
    execute: vi
      .fn()
      .mockResolvedValueOnce({ status: "unknown", sequence: 1 })
      .mockResolvedValue({ status: "ok", sequence: 1, data: detail(1, 1, "submitted") }),
    navigate: vi.fn(),
  };
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/comms/providers/:provider_id").stage(Detail),
    {
      props: { ...missionPages[2].read(detail(), detailContext), port } as never,
    },
  );
  try {
    await wrapper.get("#validate-provider-button").trigger("click");
    await flushPromises();
    expect(wrapper.get("#sync-provider-button").attributes("disabled")).toBeDefined();
    await wrapper.get("#refresh-provider-state").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenNthCalledWith(2, "refresh", {});
    await wrapper.setProps(missionPages[2].read(detail(1, 1, "submitted"), detailContext));
    expect(wrapper.get("#sync-provider-button").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#mission-provider-outcome").exists()).toBe(true);
    expect(wrapper.find("#refresh-provider-state").exists()).toBe(true);
    await wrapper.get("#refresh-provider-state").trigger("click");
    await flushPromises();
    expect(wrapper.get("#sync-provider-button").attributes("disabled")).toBeDefined();
  } finally {
    wrapper.unmount();
  }
});
test("provider registrations reject wrong resource identity, phase and effect sequence", () => {
  for (const data of [detail(1, -1), detail(1, 0, "unknown"), { ...detail(), sequence: "1" }])
    expect(() => missionPages[2].read(data, detailContext)).toThrow();
  expect(() =>
    missionPages[2].read(detail(), { ...detailContext, resourceId: "foreign" }),
  ).toThrow();
  expect(() => missionPages[1].read(creation(), detailContext)).toThrow();
});

test("confirmed archive survives a same-provider host snapshot arriving before its receipt", async () => {
  let finish!: (value: unknown) => void;
  const port = {
    execute: vi.fn(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    ),
    navigate: vi.fn(),
  };
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/comms/providers/:provider_id").stage(Detail),
    {
      props: { ...missionPages[2].read(detail(), detailContext), port } as never,
    },
  );
  const originalConfirm = Object.getOwnPropertyDescriptor(window, "confirm");
  Object.defineProperty(window, "confirm", {
    configurable: true,
    value: vi.fn().mockReturnValue(true),
  });
  try {
    await wrapper.get("#archive-provider-button").trigger("click");
    await wrapper.setProps(missionPages[2].read(detail(1, 1, "completed"), detailContext));
    finish(receipt());
    await flushPromises();
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith("/missions/mission-1/comms/providers");
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("archive-provider", {
      provider_id: "provider-1",
      expected_provider_version: 1,
      sequence: 1,
    });
  } finally {
    wrapper.unmount();
    if (originalConfirm) Object.defineProperty(window, "confirm", originalConfirm);
    else Reflect.deleteProperty(window, "confirm");
  }
});
