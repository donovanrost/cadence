import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import Form from "./CommsTransportNew.vue";
import { readForm } from "./form-validation";
import { transportFormPayload } from "./fixtures.test-support";
import type { ConfigurationField } from "./transport-new.contracts";
const context = { missionId: "mission-1" };
const payload = () => ({
  navigation: { fallback_href: "/missions/mission-1/comms/transports/new", breadcrumbs: [] },
  data: transportFormPayload(),
});
test("admitted transport form preserves server submit gating and field-only save payload", async () => {
  const p = payload();
  const wrapper = mount(Form, { props: readForm(p, context) });
  try {
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
    p.data.form.can_submit = true;
    await wrapper.setProps(readForm(p, context));
    await wrapper.get("#transport-display-name").setValue("Downlink");
    await wrapper.get("#transport-form").trigger("submit");
    expect(wrapper.emitted("save")?.[0]).toEqual([
      { transport: { display_name: "Downlink", origin: "direct", transport_kind: "tcp_socket" } },
    ]);
  } finally {
    wrapper.unmount();
  }
});
test("transport rejects contradictory origin, missing required fields, mismatched keys and unsafe links", () => {
  for (const mutate of [
    (p: ReturnType<typeof payload>) => {
      p.data.form.selected_origin = "provider_managed";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.provider.active = true;
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.fields.display_name.key = "origin";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.provider.empty_state.action.href = "//evil.test";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.page.breadcrumbs = [{ label: "Other", href: "/missions/other" }];
    },
  ]) {
    const p = payload();
    mutate(p);
    expect(() => readForm(p, context)).toThrow();
  }
  const p = payload();
  expect(() =>
    readForm({ ...p, data: { ...p.data, form: { ...p.data.form, fields: {} } } }, context),
  ).toThrow();
});
test("transport configuration keys and visibility references cannot inject or overwrite identity fields", () => {
  const p = payload();
  const field: ConfigurationField = {
    key: "host",
    wrapper_id: "host-wrapper",
    id: "host-input",
    name: "transport[host]",
    type: "text",
    label: "Host",
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
  };
  p.data.form.direct_configuration.sections = [
    {
      id: "endpoint",
      number: "01",
      title: "Endpoint",
      fields_id: "endpoint-fields",
      description: null,
      fields: [field],
    },
  ];
  expect(() => readForm(p, context)).not.toThrow();
  field.visible_when = { field: "missing", equals: "on" };
  expect(() => readForm(p, context)).toThrow();
  field.visible_when = null;
  for (const name of ["origin", "__proto__", "constructor"]) {
    field.key = name;
    field.name = "transport[" + name + "]";
    expect(() => readForm(p, context)).toThrow();
  }
});
