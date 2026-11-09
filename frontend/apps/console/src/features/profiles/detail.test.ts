import { describe, expect, it } from "vite-plus/test";
import { fieldText, type ProfileField } from "./detail.ts";

const base: ProfileField = {
  path: "frame_parameters.frame_size",
  label: "TM frame length",
  type: "integer",
  unit: "bytes",
  enum: null,
  range: { min: 1, max: 65535 },
  default: 1115,
  overridable: true,
  runtime_impact: "generation",
  help: null,
  value: 1115,
  overridden_by: 0,
};

describe("fieldText", () => {
  it("formats numbers with their unit, enum labels and booleans", () => {
    expect(fieldText(base)).toBe("1,115 bytes");
    expect(
      fieldText({
        ...base,
        type: "enum",
        unit: null,
        enum: [{ value: "tm", label: "CCSDS TM" }],
        value: "tm",
      }),
    ).toBe("CCSDS TM");
    expect(fieldText({ ...base, type: "boolean", unit: null, value: false })).toBe("No");
  });

  it("says when a value is unset and what the default is", () => {
    expect(fieldText({ ...base, value: null, default: 0 })).toBe("Not set · default 0 bytes");
    expect(fieldText({ ...base, value: null, default: null })).toBe("Not set");
  });
});
