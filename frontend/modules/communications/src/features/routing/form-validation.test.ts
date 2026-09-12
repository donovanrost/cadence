import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import Form from "./CommsRoutingNew.vue";
import { readForm } from "./form-validation";
import { routingFormPayload } from "./fixtures.test-support";
const context = { missionId: "mission-1" };
const payload = () => ({
  navigation: { fallback_href: "/missions/mission-1/comms/routing/new", breadcrumbs: [] },
  data: routingFormPayload(),
});
test("admitted routing form retains exact selected transport version in save events", async () => {
  const p = payload();
  p.data.options.transports = [{ label: "Downlink v7", value: "transport-1:7" }];
  p.data.form.fields.transport_ref.value = "transport-1:7";
  const wrapper = mount(Form, { props: readForm(p, context) });
  try {
    await wrapper.get("#routing-rule-form").trigger("submit");
    expect(wrapper.emitted("save")?.[0]).toEqual([
      { routing_rule: expect.objectContaining({ transport_ref: "transport-1:7" }) },
    ]);
  } finally {
    wrapper.unmount();
  }
});
test("routing rejects missing choices, duplicate options, unexpected field types and unsafe links", () => {
  const p = payload();
  p.data.form.fields.spacecraft_id.value = "missing";
  expect(() => readForm(p, context)).toThrow();
  p.data.options.spacecraft = [{ label: "A", value: "missing" }];
  expect(() => readForm(p, context)).not.toThrow();
  p.data.options.spacecraft.push({ label: "A again", value: "missing" });
  expect(() => readForm(p, context)).toThrow();
  const wrong = payload();
  wrong.data.form.fields.direction.type = "text";
  expect(() => readForm(wrong, context)).toThrow();
  const unsafe = payload();
  unsafe.data.form.actions.cancel.href = "javascript:alert(1)";
  expect(() => readForm(unsafe, context)).toThrow();
});
test("routing bounds options and rejects a form for another mission", () => {
  const p = payload();
  p.data.options.spacecraft = Array.from({ length: 101 }, (_, i) => ({
    label: "A",
    value: String(i),
  }));
  expect(() => readForm(p, context)).toThrow();
  expect(() => readForm(payload(), { missionId: "other" })).toThrow();
});
