import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import TransportCreation from "./TransportCreation.vue";
import { transportFormPayload } from "./fixtures.test-support";
import { admitValidation } from "./validation-receipt";
test("current validation enables transport save without replacing the draft and updates its review", async () => {
  const port = {
    execute: vi
      .fn()
      .mockResolvedValueOnce({
        result: {
          valid: true,
          transport_review: { origin: "direct", endpoint: "tcp://localhost:5000" },
        },
      })
      .mockResolvedValue({
        result: { navigation: { href: "/missions/mission-1/comms/transports/t1" } },
      }),
    navigate: vi.fn(),
  };
  const wrapper = mount(TransportCreation, {
    props: { ...transportFormPayload(), context: { missionId: "mission-1" }, port },
  });
  try {
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
    const node = wrapper.get("#transport-display-name").element;
    await wrapper.get("#transport-display-name").setValue("Downlink");
    await flushPromises();
    expect(wrapper.get("#transport-display-name").element).toBe(node);
    expect((node as HTMLInputElement).value).toBe("Downlink");
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeUndefined();
    expect(wrapper.get("#summary").text()).toContain("tcp://localhost:5000");
    await wrapper.get("#transport-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenLastCalledWith("save", {
      transport: { display_name: "Downlink", origin: "direct", transport_kind: "tcp_socket" },
    });
    expect(port.navigate).toHaveBeenCalledWith("/missions/mission-1/comms/transports/t1");
  } finally {
    wrapper.unmount();
  }
});
test("transport review admission rejects partial, wrong-origin and negative validation receipts", () => {
  for (const receipt of [
    { valid: true },
    { valid: false },
    { valid: true, transport_review: { origin: "unknown", endpoint: "tcp" } },
  ]) {
    expect(() => admitValidation(receipt)).toThrow();
  }
});
