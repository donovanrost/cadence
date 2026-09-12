import { mount, flushPromises } from "@vue/test-utils";
import { defineComponent } from "vue";
import { expect, test } from "vite-plus/test";
import ReadSurface from "./ReadSurface.vue";
import { admitReadSurface } from "./read-registry";
import { readSurfaces } from "./read-registry";
import LegacyReadSurface from "../../../apps/comms-overview/src/CommsCanonicalSurface.vue";
test("the historical entry is only an adapter to eight admitted feature registrations", () => {
  expect(LegacyReadSurface).toBe(ReadSurface);
  expect(Object.keys(readSurfaces)).toEqual([
    "overview",
    "validation",
    "transports",
    "transport",
    "routing",
    "routing_detail",
    "ground_stations",
    "ground_station",
  ]);
});
import { context, directoryPayload } from "./features/transports/read-fixtures.test-support";

test("unknown surfaces, unsupported versions and bad DTOs are contained with a retry event", async () => {
  for (const override of [
    { surfaceId: "unknown" },
    { version: 2 },
    { payload: {} },
    { context: { missionId: "other" } },
  ]) {
    const wrapper = mount(ReadSurface, {
      props: {
        surfaceId: "transports",
        version: 1,
        context,
        payload: directoryPayload(),
        ...override,
      },
    });
    try {
      expect(wrapper.find("#comms-read-unavailable").exists()).toBe(true);
      expect(wrapper.find("#comms-transports-directory").exists()).toBe(false);
      await wrapper.get("#retry-comms-read").trigger("click");
      expect(wrapper.emitted("retry")).toEqual([[]]);
    } finally {
      wrapper.unmount();
    }
  }
  expect(() => admitReadSurface("__proto__", 1, {}, context)).toThrow();
});
test("renderer failure stays inside the module boundary", async () => {
  const broken = defineComponent({
    setup() {
      throw new Error("private renderer failure");
    },
  });
  const wrapper = mount(ReadSurface, {
    props: { surfaceId: "transports", version: 1, context, payload: directoryPayload() },
    global: { stubs: { TransportDirectory: broken } },
  });
  await flushPromises();
  try {
    expect(wrapper.find("#comms-read-unavailable").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private renderer failure");
  } finally {
    wrapper.unmount();
  }
});
test("new valid props recover an invalid read without retaining stale content", async () => {
  const wrapper = mount(ReadSurface, {
    props: { surfaceId: "transports", version: 1, context, payload: {} },
  });
  try {
    await wrapper.setProps({ payload: directoryPayload() });
    expect(wrapper.find("#comms-read-unavailable").exists()).toBe(false);
    expect(wrapper.find("#comms-transports-directory").exists()).toBe(true);
    await wrapper.setProps({ context: { missionId: "other" } });
    expect(wrapper.find("#comms-transports-directory").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});
