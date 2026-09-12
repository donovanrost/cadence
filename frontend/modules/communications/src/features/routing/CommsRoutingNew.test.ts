import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsRoutingNew from "./CommsRoutingNew.vue";
import { routingFormPayload } from "./fixtures.test-support";

test("routing draft emits the exact spacecraft and transport binding through feature events", async () => {
  const props = routingFormPayload();
  props.options.spacecraft = [{ label: "Firebird", value: "spacecraft-1" }];
  props.options.transports = [{ label: "Downlink", value: "transport-1" }];
  props.options.directions = [{ label: "Downlink", value: "downlink" }];
  props.options.roles = [{ label: "Primary", value: "primary" }];
  const wrapper = mount(CommsRoutingNew, { props });
  try {
    for (const [key, value] of Object.entries({
      display_name: "Downlink",
      purpose_label: "Telemetry",
      spacecraft_id: "spacecraft-1",
      transport_ref: "transport-1",
      direction: "downlink",
      role: "primary",
    })) {
      await wrapper.get("#routing_rule_" + key).setValue(value);
    }
    const input = {
      routing_rule: {
        display_name: "Downlink",
        purpose_label: "Telemetry",
        spacecraft_id: "spacecraft-1",
        transport_ref: "transport-1",
        direction: "downlink",
        role: "primary",
      },
    };
    expect(wrapper.emitted("validate")?.at(-1)).toEqual([input]);
    await wrapper.get("#routing-rule-form").trigger("submit");
    expect(wrapper.emitted("save")).toEqual([[input]]);
    expect(wrapper.get("a#cancel").attributes("href")).toBe("/missions/mission-1/comms/routing");
  } finally {
    wrapper.unmount();
  }
});
