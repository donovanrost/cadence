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
});
