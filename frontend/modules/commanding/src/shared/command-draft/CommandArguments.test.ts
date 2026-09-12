import { record } from "@cadence/plugin-sdk/admission";
import { fixtureString } from "../../../../../test-support/json-fixture";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommandArguments from "./CommandArguments.vue";
import type { Argument } from "./contracts";
const maximum = "18446744073709551615";
const spec = (changes: Partial<Argument> = {}): Argument => ({
  id: "counter",
  name: "counter",
  type: "integer",
  required: true,
  description: null,
  default_value_json: null,
  fixed_value_json: null,
  hazardous_values_json: "[]",
  ...changes,
});
function form(argument = spec(), supplied?: string) {
  return mount(CommandArguments, {
    props: {
      arguments: [argument],
      idPrefix: "exact",
      ...(supplied === undefined ? {} : { supplied }),
    },
  });
}
function hasCollector(value: unknown): value is { collect: () => unknown } {
  return record(value) && typeof value.collect === "function";
}
function collect(instance: unknown): string {
  if (!hasCollector(instance)) throw Error("The mounted arguments must expose collect");
  return fixtureString(instance.collect());
}
test.each([maximum, "-9223372036854775808", "9007199254740993"])(
  "mounted input preserves %s",
  async (value) => {
    const w = form();
    await w.get('[data-argument-name="counter"]').setValue(value);
    expect(collect(w.vm)).toBe(`{"counter":${value}}`);
    expect(w.emitted("edited")).toHaveLength(1);
    w.unmount();
  },
);
test("defaults, fixed values and hazards display exact digits while omitted intent stays omitted", async () => {
  const w = form(
    spec({ required: false, default_value_json: maximum, hazardous_values_json: `[${maximum}]` }),
  );
  expect(w.text()).toContain(`Uses default: ${maximum}`);
  expect(w.text()).toContain(`Hazardous values: [${maximum}]`);
  expect(collect(w.vm)).toBe("{}");
  await w.get('[data-argument-enabled="counter"]').setValue(true);
  expect(w.get<HTMLInputElement>('[data-argument-name="counter"]').element.value).toBe(maximum);
  expect(collect(w.vm)).toBe(`{"counter":${maximum}}`);
  w.unmount();
  const fixed = form(spec({ fixed_value_json: maximum }));
  expect(fixed.text()).toContain(`Fixed: ${maximum}`);
  expect(fixed.find('[data-argument-name="counter"]').exists()).toBe(false);
  expect(collect(fixed.vm)).toBe("{}");
  fixed.unmount();
});
test("reopened draft retains exact numeric and textual enum intent", async () => {
  for (const raw of [maximum, JSON.stringify(maximum)]) {
    const w = form(spec({ type: "enumerated" }), `{"counter":${raw}}`);
    expect(w.get<HTMLInputElement>('[data-argument-name="counter"]').element.value).toBe(maximum);
    expect(collect(w.vm)).toBe(`{"counter":${raw}}`);
    w.unmount();
  }
});
test("false, zero and empty string remain distinct from omitted values", () => {
  for (const [type, raw] of [
    ["boolean", "false"],
    ["integer", "0"],
    ["string", '""'],
  ] as const) {
    const w = form(spec({ type }), `{"counter":${raw}}`);
    expect(collect(w.vm)).toBe(`{"counter":${raw}}`);
    w.unmount();
  }
});
test("fractional integer input fails while floats retain finite number semantics", async () => {
  const integer = form();
  await integer.get('[data-argument-name="counter"]').setValue("9007199254740993.1");
  expect(() => collect(integer.vm)).toThrow("integer");
  integer.unmount();
  const float = form(spec({ type: "float" }));
  for (const value of ["1.25", "1e20", "-0.125e-2"]) {
    await float.get('[data-argument-name="counter"]').setValue(value);
    expect(collect(float.vm)).toBe(`{"counter":${JSON.stringify(Number(value))}}`);
  }
  await float.get('[data-argument-name="counter"]').setValue("1e9999");
  expect(() => collect(float.vm)).toThrow("number");
  float.unmount();
});
