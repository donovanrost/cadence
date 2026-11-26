import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  confirmsReset,
  fieldTag,
  resetConfirm,
  resetLine,
  sectionSource,
  setHereCount,
  settingsReader,
} from "./api.ts";

/** api 14455857d: one mission section can mix per-field sources (ux SettingsAuditProviders.md). */
function section(sources: readonly (string | null)[]) {
  const r = decode(settingsReader, {
    sections: [
      {
        key: "cadence.governance",
        title: "Governance",
        purpose: null,
        locked: false,
        version: null,
        fields: sources.map((source, i) => ({
          path: `f${i}`,
          label: `F${i}`,
          type: "string",
          unit: null,
          enum: null,
          range: null,
          default: null,
          required: false,
          help: null,
          visible_when: null,
          value: "x",
          source,
          inherited_value: "y",
        })),
      },
    ],
    permissions: ["settings.edit"],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  const [s] = r.value.sections;
  if (!s) throw new Error("no section");
  return s;
}

describe("per-field settings sources", () => {
  it("tags each field by its own source", () => {
    const s = section(["organization", "mission", "default"]);
    expect(s.fields.map(fieldTag)).toEqual([
      "Inherited from org",
      "Set for this mission",
      "Default",
    ]);
  });

  it("gives no tag when the source is absent, null or a value this console doesn't know", () => {
    const [unknown, none] = section(["inherited_from_constellation", null]).fields;
    if (!unknown || !none) throw new Error("no fields");
    expect(unknown.source).toBe("unrecognized");
    expect(fieldTag(unknown)).toBeNull();
    expect(fieldTag(none)).toBeNull();
    expect(fieldTag({ ...none, source: undefined })).toBeNull();
  });

  it("reads a section as the mission's when any field is set for it", () => {
    expect(sectionSource(section(["organization", "mission"]))).toBe("mission");
    expect(sectionSource(section(["organization", "default"]))).toBe("organization");
  });

  it("words a Reset (the old value), its confirm, and the header count (ux)", () => {
    const s = section(["mission", "organization", "mission"]);
    const [f] = s.fields;
    if (!f) throw new Error("no field");
    expect(resetLine(f, 5)).toBe("F0 follows the organization again (was x). Saved as v5.");
    expect(resetConfirm(f, "Acme Space")).toBe("F0 will follow Acme Space: y.");
    expect(setHereCount(s)).toBe("2 set for this mission");
    expect(setHereCount(section(["organization"]))).toBeNull();
    expect(confirmsReset("cadence.governance")).toBe(true);
  });
});
