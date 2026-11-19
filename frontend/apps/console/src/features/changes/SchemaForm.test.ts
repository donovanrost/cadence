import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { kindSchemaReader } from "./kindSchema.ts";
import SchemaForm from "./SchemaForm.vue";

const read = decode(kindSchemaReader, {
  kind: "transport",
  fields: [
    {
      path: "configuration.mode",
      label: "TCP Mode",
      type: "enum",
      unit: null,
      enum: [
        { value: "listen", label: "TCP server (listen)" },
        { value: "connect", label: "TCP client (connect)" },
      ],
      range: null,
      default: "listen",
      required: false,
      help: null,
      visible_when: null,
    },
  ],
});
if (!read.ok) throw read.error;
const schema = read.value;

describe("SchemaForm notes (a kind's form rules; U83)", () => {
  it("puts an info line under its field, and nothing without one", () => {
    const line = "This transport will stop sharing its listener.";
    const props = { schema, errors: {}, modelValue: { "configuration.mode": "connect" } };
    const noted = mount(SchemaForm, { props: { ...props, notes: { "configuration.mode": line } } });
    expect(noted.text()).toContain(line);
    expect(mount(SchemaForm, { props }).text()).not.toContain(line);
  });

  // #243 (mms-ux, fe-setup): the note is read with its field (the field's hint, aria-describedby)
  // and said once from a status line, since it appears while focus is on the control.
  it("ties the note to its field and says it from a status line", () => {
    const line = "This transport will stop sharing its listener.";
    const w = mount(SchemaForm, {
      props: {
        schema,
        errors: {},
        modelValue: { "configuration.mode": "connect" },
        notes: { "configuration.mode": line },
      },
      attachTo: document.body,
    });
    const control = w.get("select, button[role='combobox'], [aria-describedby]");
    const ids = (control.attributes("aria-describedby") ?? "").split(" ").filter(Boolean);
    const described = ids.map((id) => document.getElementById(id)?.textContent ?? "").join(" ");
    expect(described).toContain(line);
    expect(w.get('p.sr-only[role="status"]').text()).toBe(line);
    w.unmount();
  });
});
