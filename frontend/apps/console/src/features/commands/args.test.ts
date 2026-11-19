import { describe, expect, it } from "vite-plus/test";
import type { CommandArgument } from "./api.ts";
import { argInput, checkArg, initialText, UNSUPPORTED_ARG } from "./args.ts";

const arg = (overrides: Partial<CommandArgument>): CommandArgument => ({
  id: "a",
  name: "x",
  description: null,
  type: "integer",
  required: true,
  default_value_json: null,
  fixed_value_json: null,
  hazardous_values_json: [],
  choices: [],
  valid_range: null,
  unit: null,
  current_point: undefined,
  ...overrides,
});

describe("command arguments", () => {
  it("builds the input from the catalog", () => {
    expect(
      argInput(
        arg({ type: "float", valid_range: { minimum_json: "-40.0", maximum_json: "60.0" } }),
      ),
    ).toEqual({ kind: "number", integer: false, min: -40, max: 60 });
    expect(
      argInput(arg({ valid_range: { minimum_json: "0", maximum_json: "18446744073709551615" } })),
    ).toEqual({ kind: "number", integer: true, min: 0 });
    expect(argInput(arg({ fixed_value_json: '"SAFE"' }))).toEqual({ kind: "fixed", text: "SAFE" });
    expect(
      argInput(arg({ type: "enumerated", choices: [{ label: "ON", value_json: "1" }] })),
    ).toEqual({ kind: "choice", options: [{ value: "1", label: "ON" }] });
  });

  it("starts from the default or the fixed value", () => {
    expect(initialText(arg({ default_value_json: "5" }))).toBe("5");
    expect(initialText(arg({ type: "string", default_value_json: '"hi"' }))).toBe("hi");
    expect(initialText(arg({}))).toBe("");
  });

  it("keeps 64-bit integers exact and enforces the range", () => {
    const big = arg({ valid_range: { minimum_json: "0", maximum_json: "18446744073709551615" } });
    expect(checkArg(big, "18446744073709551615")).toEqual({
      ok: true,
      json: "18446744073709551615",
      hazardous: false,
    });
    expect(checkArg(big, "18446744073709551616")).toEqual({
      ok: false,
      reason: "At most 18446744073709551615.",
    });
    expect(checkArg(big, "1.5")).toEqual({ ok: false, reason: "Enter a whole number." });
  });

  it("checks floats, enums, booleans, strings, hex and required", () => {
    const temp = arg({
      type: "float",
      unit: "degC",
      valid_range: { minimum_json: "-40.0", maximum_json: "60.0" },
    });
    expect(checkArg(temp, "61")).toEqual({ ok: false, reason: "At most 60.0 degC." });
    expect(checkArg(temp, "21.5")).toMatchObject({ ok: true, json: "21.5" });
    expect(
      checkArg(arg({ type: "enumerated", choices: [{ label: "1", value_json: "1" }] }), "2").ok,
    ).toBe(false);
    expect(checkArg(arg({ type: "boolean" }), "true")).toMatchObject({ ok: true, json: "true" });
    expect(checkArg(arg({ type: "string" }), "hello")).toMatchObject({ json: '"hello"' });
    expect(checkArg(arg({ type: "binary" }), "0a1")).toMatchObject({ ok: false });
    expect(checkArg(arg({}), "")).toEqual({ ok: false, reason: "Required." });
    expect(checkArg(arg({ required: false }), "")).toMatchObject({ ok: true, json: "null" });
  });

  it("flags hazardous values", () => {
    expect(checkArg(arg({ hazardous_values_json: ["0"] }), "0")).toMatchObject({
      ok: true,
      hazardous: true,
    });
  });
});

describe("an argument type the console doesn't know (lead)", () => {
  it("renders read-only and can't be staged, unless the catalog fixes its value", () => {
    expect(argInput(arg({ type: "unrecognized" }))).toEqual({ kind: "unsupported" });
    expect(checkArg(arg({ type: "unrecognized" }), "1")).toEqual({
      ok: false,
      reason: UNSUPPORTED_ARG,
    });
    const fixed = arg({ type: "unrecognized", fixed_value_json: "3" });
    expect(argInput(fixed).kind).toBe("fixed");
    expect(checkArg(fixed, "").ok).toBe(true);
  });
});
