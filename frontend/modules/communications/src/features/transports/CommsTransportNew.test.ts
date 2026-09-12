import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsTransportNew from "./CommsTransportNew.vue";
import { transportFormPayload } from "./fixtures.test-support";
import type { ConfigurationField } from "./transport-new.contracts";

test("configuration changes validate the currently visible fields, including newly revealed values", async () => {
  const props = transportFormPayload();
  const field = (key: string): ConfigurationField => ({
    key,
    wrapper_id: key + "-wrapper",
    id: key + "-input",
    name: "transport[" + key + "]",
    type: "text",
    label: key,
    required: true,
    placeholder: null,
    help: null,
    step: null,
    min: null,
    max: null,
    default: "",
    value: "",
    options: [],
    visible: true,
    visible_when: null,
  });
  const framing = {
    ...field("framing_mode"),
    type: "select" as const,
    value: "raw",
    options: [
      { label: "Raw", value: "raw", disabled: false },
      { label: "Fixed", value: "fixed", disabled: false },
    ],
  };
  const size = {
    ...field("frame_size"),
    value: "64",
    visible_when: { field: "framing_mode", equals: "fixed" },
  };
  props.form.direct_configuration.sections = [
    {
      id: "framing",
      number: "01",
      title: "Framing",
      fields_id: "framing-fields",
      description: null,
      fields: [framing, size],
    },
  ];
  const wrapper = mount(CommsTransportNew, { props });
  try {
    expect(wrapper.find("#frame_size-input").exists()).toBe(false);
    await wrapper.get("#framing_mode-input").setValue("fixed");
    expect(wrapper.find("#frame_size-input").exists()).toBe(true);
    expect(wrapper.emitted("validate")?.at(-1)).toEqual([
      { transport: expect.objectContaining({ framing_mode: "fixed", frame_size: "64" }) },
    ]);
    await wrapper.get("#framing_mode-input").setValue("raw");
    expect(
      (wrapper.emitted("validate")?.at(-1)?.[0] as { transport: Record<string, string> }).transport,
    ).not.toHaveProperty("frame_size");
  } finally {
    wrapper.unmount();
  }
});

test("direct transport validation and save exclude unrelated provider fields", async () => {
  const props = transportFormPayload();
  props.form.can_submit = true;
  props.form.fields.origin.options = [{ label: "Direct", value: "direct", disabled: false }];
  props.form.fields.transport_kind.options = [
    { label: "TCP", value: "tcp_socket", disabled: false },
  ];
  const wrapper = mount(CommsTransportNew, { props });
  try {
    await wrapper.get("#transport-display-name").setValue("Mission downlink");
    const input = {
      transport: {
        display_name: "Mission downlink",
        origin: "direct",
        transport_kind: "tcp_socket",
      },
    };
    expect(wrapper.emitted("validate")?.at(-1)).toEqual([input]);
    await wrapper.get("#transport-form").trigger("submit");
    expect(wrapper.emitted("save")).toEqual([[input]]);
    expect(wrapper.get("a#cancel").attributes("href")).toBe("/missions/mission-1/comms/transports");
  } finally {
    wrapper.unmount();
  }
});

test("transport submission remains disabled while the server says setup is incomplete", () => {
  const wrapper = mount(CommsTransportNew, { props: transportFormPayload() });
  try {
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
  } finally {
    wrapper.unmount();
  }
});
