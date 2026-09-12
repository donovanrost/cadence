import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import RoutingCreation from "./RoutingCreation.vue";
import { routingFormPayload } from "./fixtures.test-support";
test("validation rejection leaves routing inputs mounted and can be rechecked without requerying", async () => {
  const port = {
    execute: vi
      .fn()
      .mockRejectedValueOnce(new Error("private"))
      .mockResolvedValue({ result: { valid: true } }),
    navigate: vi.fn(),
  };
  const wrapper = mount(RoutingCreation, {
    props: { ...routingFormPayload(), context: { missionId: "mission-1" }, port },
  });
  try {
    const node = wrapper.get("#routing_rule_display_name").element;
    await wrapper.get("#routing_rule_display_name").setValue("Downlink");
    await flushPromises();
    expect(wrapper.get("#routing_rule_display_name").element).toBe(node);
    expect(wrapper.text()).not.toContain("private");
    await wrapper.get("#routing-rule-form-feedback-retry").trigger("click");
    await flushPromises();
    expect(wrapper.get("#create-routing-rule-button").attributes("disabled")).toBeUndefined();
    expect((node as HTMLInputElement).value).toBe("Downlink");
  } finally {
    wrapper.unmount();
  }
});
