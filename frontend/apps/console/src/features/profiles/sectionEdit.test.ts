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
  it("keeps limits read-only; framing edits since #19 was lifted", () => {
    expect([
      editableSection("framing"),
      editableSection("limits"),
      editableSection("catalog"),
    ]).toEqual([true, false, true]);
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

describe("describePreview error lines (ux)", () => {
  it("says 'Catalog revision 16 doesn't exist.' with the typed value", async () => {
    const { decode } = await import("@/api");
    const { previewReader } = await import("@/features/changes/actions.ts");
    const { describePreview } = await import("./sectionEdit.ts");
    const p = decode(previewReader, {
      verdict: "no_go",
      checks: [
        {
          key: "validation",
          verdict: "no_go",
          items: [
            {
              kind: "spacecraft_profile",
              errors: [
                { path: "catalog_revision_id", message: "That catalog revision doesn't exist" },
              ],
            },
          ],
        },
      ],
      effects: [],
    });
    if (!p.ok) throw p.error;
    expect(
      describePreview(
        p.value,
        { catalog_revision_id: "Catalog revision" },
        { catalog_revision_id: "16" },
      ),
    ).toEqual({ tone: "crit", text: "NO-GO: Catalog revision 16 doesn't exist." });
  });
});

describe("describePreview keeps (ux, Profile.md P4)", () => {
  it("gives framing-governed spacecraft their own sentence", async () => {
    const { decode } = await import("@/api");
    const { previewReader } = await import("@/features/changes/index.ts");
    const { describePreview } = await import("./sectionEdit.ts");
    const keep = (id: string, code: string, reason: string) => ({
      spacecraft: { id, name: id },
      reason,
      code,
    });
    const p = decode(previewReader, {
      verdict: "go",
      checks: [],
      effects: [
        {
          op_id: "o1",
          changes: 497,
          keeps: [
            keep("a", "framing_governed", "framing is governed by its configuration review"),
            keep("b", "framing_governed", "framing is governed by its configuration review"),
            keep("c", "older_profile_version", "stays on v3"),
          ],
        },
      ],
    });
    if (!p.ok) throw p.error;
    expect(describePreview(p.value).text).toBe(
      "Checks pass · changes 497 spacecraft · keeps 1 spacecraft (stays on v3) · 2 keep their framing: it's set in their own configuration review.",
    );
    const { previewCounts } = await import("./sectionEdit.ts");
    expect(previewCounts(p.value)).toEqual({ changes: 497, keeps: 3 });
  });
});
