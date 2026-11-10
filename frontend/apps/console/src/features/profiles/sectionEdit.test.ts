import { describe, expect, it } from "vite-plus/test";
import type { ProfileSection } from "./detail.ts";
import { editableSection, schemaFieldsOf, sectionOp, sectionValues } from "./sectionEdit.ts";

const section: ProfileSection = {
  key: "commanding",
  label: "Commanding",
  fields: [
    {
      path: "commanding.release_window_s",
      label: "Release window",
      type: "integer",
      unit: "s",
      enum: null,
      range: { min: 0, max: 86_400 },
      default: 3600,
      overridable: true,
      runtime_impact: "none",
      help: null,
      value: 7200,
      overridden_by: 0,
    },
  ],
};

describe("profile section edit", () => {
  it("keeps framing and limits read-only", () => {
    expect([
      editableSection("framing"),
      editableSection("limits"),
      editableSection("catalog"),
    ]).toEqual([false, false, true]);
  });
  it("turns section fields into a form and a profile update op", () => {
    const fields = schemaFieldsOf(section);
    expect(sectionValues(section, fields)).toEqual({ "commanding.release_window_s": "2h 00m" });
    expect(sectionOp("prof_1", [{ path: "commanding.release_window_s", value: 5400 }])).toEqual({
      kind: "spacecraft_profile",
      action: "update",
      entity_id: "prof_1",
      changes: [{ path: "commanding.release_window_s", value: 5400 }],
    });
  });
});
