import { record } from "@cadence/plugin-sdk/admission";
import { fixtureString } from "../../../../../test-support/json-fixture";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommandArguments from "./CommandArguments.vue";
import type { Argument } from "./contracts";
const maximum = "18446744073709551615";
const choices = (...values: string[]) =>
  values.map((value) => ({ label: value, value_json: value }));
const spec = (changes: Partial<Argument> = {}): Argument => ({
  id: "counter",
  name: "counter",
  type: "integer",
  required: true,
  description: null,
  default_value_json: null,
  fixed_value_json: null,
  hazardous_values_json: "[]",
  choices: [],
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
test("defaults are visible and submitted exactly; fixed arguments stay read-only", () => {
  const w = form(
    spec({ required: false, default_value_json: maximum, hazardous_values_json: `[${maximum}]` }),
  );
  expect(w.text()).toContain(`Hazardous values: [${maximum}]`);
  expect(w.get<HTMLInputElement>('[data-argument-name="counter"]').element.value).toBe(maximum);
  expect(w.find('input[type="checkbox"]').exists()).toBe(false);
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
    const w = form(spec({ type: "enumerated", choices: choices(maximum) }), `{"counter":${raw}}`);
    expect(w.get<HTMLInputElement>(`input[value="${maximum}"]`).element.checked).toBe(true);
    expect(collect(w.vm)).toBe(`{"counter":${raw}}`);
    w.unmount();
  }
});
test("small enumerations take one click and submit the catalog value", async () => {
  const w = form(spec({ type: "enumerated", choices: choices("1", "2") }));
  expect(w.findAll('input[type="radio"]')).toHaveLength(2);
  expect(w.find("select").exists()).toBe(false);
  expect(w.find('[data-argument-enabled="counter"]').exists()).toBe(false);
  expect(() => collect(w.vm)).toThrow("Choose a value");
  await w.get('input[value="2"]').setValue(true);
  expect(collect(w.vm)).toBe('{"counter":2}');
  expect(w.emitted("edited")).toHaveLength(1);
  w.unmount();
});
test("optional enums still require an explicit choice, including zero", async () => {
  const w = form(spec({ type: "enumerated", required: false, choices: choices("0", "1") }));
  expect(() => collect(w.vm)).toThrow("Choose a value for counter");
  await w.get('input[value="0"]').setValue(true);
  expect(collect(w.vm)).toBe('{"counter":0}');
  expect(w.find('button[aria-label="Omit counter"]').exists()).toBe(false);
  w.unmount();
});
test("default choice is submitted explicitly, including when reopening omitted intent", async () => {
  const definition = spec({
    type: "enumerated",
    default_value_json: "1",
    choices: [
      { label: "Primary", value_json: "1" },
      { label: "Backup", value_json: "2" },
    ],
  });
  const w = form(definition, "{}");
  expect(w.get<HTMLInputElement>('input[value="1"]').element.checked).toBe(true);
  expect(collect(w.vm)).toBe('{"counter":1}');
  await w.get('input[value="2"]').setValue(true);
  expect(collect(w.vm)).toBe('{"counter":2}');
  await w.get('input[value="1"]').setValue(true);
  expect(collect(w.vm)).toBe('{"counter":1}');
  expect(w.find('button[aria-label="Use default for counter"]').exists()).toBe(false);
  expect(w.get<HTMLInputElement>('input[value="1"]').element.checked).toBe(true);
  w.unmount();
  const fixed = form({ ...definition, fixed_value_json: "2" });
  expect(fixed.text()).toContain("Fixed: Backup");
  expect(fixed.find("input").exists()).toBe(false);
  expect(collect(fixed.vm)).toBe("{}");
  fixed.unmount();
});
test("larger enumerations use a select and reject values outside the definition", async () => {
  const definition = spec({
    type: "enumerated",
    choices: choices("0", "1", "2", "3", "4", "5", "6"),
  });
  const w = form(definition, '{"counter":9}');
  expect(w.find('input[type="radio"]').exists()).toBe(false);
  expect(() => collect(w.vm)).toThrow("Choose a value");
  await w.get("select").setValue("6");
  expect(collect(w.vm)).toBe('{"counter":6}');
  w.unmount();
});
test.each([
  ["integer", "0", "0"],
  ["float", "1.25", "1.25"],
  ["string", "payload", '"payload"'],
  ["binary", "00ff", '"00ff"'],
  ["boolean", "false", "false"],
] as const)(
  "%s arguments without defaults require entry even when optional in the catalog",
  async (type, input, raw) => {
    const w = form(spec({ type, required: false }));
    expect(w.get('[data-argument-name="counter"]').isVisible()).toBe(true);
    expect(() => collect(w.vm)).toThrow("a value for counter");
    await w.get('[data-argument-name="counter"]').setValue(input);
    expect(collect(w.vm)).toBe(`{"counter":${raw}}`);
    w.unmount();
  },
);
test("false, zero and intentional empty strings remain explicit values", () => {
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
