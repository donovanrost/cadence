import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { displayValue, schemaFieldReader } from "@/features/changes/index.ts";
import { maxGapFact } from "./templates.ts";

/** Fixture: domain e99fe3830, the template schema's max-gap field (the requirement form's words). */
function gapField() {
  const r = decode(schemaFieldReader, {
    path: "requirement.max_gap_seconds",
    label: "Longest gap between contacts",
    type: "integer",
    unit: "s",
    enum: null,
    range: { min: 600, max: 604800 },
    default: null,
    required: false,
    help: null,
    visible_when: null,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

describe("template max gap (#74)", () => {
  it("shows the schema's label and value, 'No limit' when empty, nothing before the schema", () => {
    const f = gapField();
    expect(maxGapFact([f], { requirement: { max_gap_seconds: 3600 } })).toEqual({
      key: "requirement.max_gap_seconds",
      label: "Longest gap between contacts",
      value: displayValue(f, 3600),
      mono: true,
    });
    expect(maxGapFact([f], { requirement: {} })?.value).toBe("No limit");
    expect(maxGapFact(null, {})).toBeNull();
  });
});
