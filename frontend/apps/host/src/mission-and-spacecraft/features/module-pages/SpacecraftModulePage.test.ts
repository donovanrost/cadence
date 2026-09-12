import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import SpacecraftModulePage from "./SpacecraftModulePage.vue";
import { admitSpacecraftPages } from "./contributions";
import {
  spacecraftRoutingContribution,
  SpacecraftRouting,
} from "@cadence/communications/spacecraft-routing";
import {
  spacecraftRoutingContext as context,
  spacecraftRoutingSnapshot,
} from "../../../../../../modules/communications/src/features/routing/spacecraft-routing.test-support";

test("host admits the feature and retries unavailable snapshots without interpreting routing DTOs", async () => {
  const refresh = vi.fn().mockResolvedValue(undefined);
  const wrapper = mount(SpacecraftModulePage, {
    props: {
      contributionId: "comms.spacecraft-routing",
      context,
      snapshot: { ...spacecraftRoutingSnapshot(), status: "unavailable" },
      refresh,
    },
  });
  expect(wrapper.find("#spacecraft-module-unavailable").exists()).toBe(true);
  await wrapper.get("#spacecraft-module-retry").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  await wrapper.setProps({ snapshot: spacecraftRoutingSnapshot() });
  expect(wrapper.find("#spacecraft-routing-rule-rule-1").exists()).toBe(true);
  wrapper.unmount();
});
test("host rejects unknown identities, versions, slots, resource scopes and malformed feature data", async () => {
  const wrapper = mount(SpacecraftModulePage, {
    props: {
      contributionId: "comms.spacecraft-routing",
      context,
      snapshot: spacecraftRoutingSnapshot(),
      refresh: vi.fn(),
    },
  });
  const valid = spacecraftRoutingSnapshot();
  for (const snapshot of [
    null,
    { ...valid, id: "unknown" },
    { ...valid, slot: "administration.diagnostics" },
    { ...valid, version: 2 },
    ...["organizationId", "missionId", "spacecraftId"].map((key) => ({
      ...valid,
      context: { ...context, [key]: "other" },
    })),
    { ...valid, data: {} },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#spacecraft-module-unavailable").exists()).toBe(true);
    expect(wrapper.find("#spacecraft-routing-rules").exists()).toBe(false);
  }
  await wrapper.setProps({ snapshot: valid, contributionId: "__proto__" });
  expect(wrapper.find("#spacecraft-module-unavailable").exists()).toBe(true);
  wrapper.unmount();
});
test("compiled registration rejects duplicate identities and unsupported slots", () => {
  expect(() =>
    admitSpacecraftPages([spacecraftRoutingContribution, spacecraftRoutingContribution]),
  ).toThrow();
  expect(() =>
    admitSpacecraftPages([{ ...spacecraftRoutingContribution, version: 2 } as never]),
  ).toThrow();
});
test("renderer failures are contained and a fresh snapshot can recover", async () => {
  const setup = vi.spyOn(SpacecraftRouting, "setup").mockImplementation(() => {
    throw new Error("private routing renderer failure");
  });
  const wrapper = mount(SpacecraftModulePage, {
    props: {
      contributionId: "comms.spacecraft-routing",
      context,
      snapshot: spacecraftRoutingSnapshot(),
      refresh: vi.fn(),
    },
  });
  try {
    await wrapper.vm.$nextTick();
    expect(wrapper.find("#spacecraft-module-unavailable").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private routing renderer failure");
    setup.mockRestore();
    await wrapper.setProps({ snapshot: spacecraftRoutingSnapshot() });
    expect(wrapper.find("#spacecraft-routing-rule-rule-1").exists()).toBe(true);
  } finally {
    wrapper.unmount();
    setup.mockRestore();
  }
});
