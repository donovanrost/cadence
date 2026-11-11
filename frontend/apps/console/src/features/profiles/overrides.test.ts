import { describe, expect, it } from "vite-plus/test";
import type { ProfileField, ProfileSection } from "./detail.ts";
import { overridableFields, overrideKey, overrideOp, overrideSchemaField } from "./overrides.ts";

const field = (path: string, label: string, overridable = true): ProfileField => ({
  path,
  label,
  type: "integer",
  unit: null,
  enum: null,
  range: null,
  default: null,
  overridable,
  runtime_impact: "generation",
  help: null,
  value: 1279,
  overridden_by: 0,
});

const sections: ProfileSection[] = [
  {
    key: "framing",
    label: "Framing",
    fields: [
      field("frame_parameters.frame_size", "TM frame length"),
      field("packet_protocol", "Packet protocol", false),
    ],
  },
  { key: "catalog", label: "Catalog", fields: [field("catalog_revision_id", "Catalog revision")] },
];

describe("profile overrides", () => {
  it("writes the override key with slashes, so the server doesn't nest it", () => {
    expect(overrideKey("frame_parameters.frame_size")).toBe("frame_parameters/frame_size");
    expect(overrideKey("catalog_revision_id")).toBe("catalog_revision_id");
  });

  it("stages a set as {value, reason} and a reset as null on the spacecraft", () => {
    expect(
      overrideOp("sc_1", "catalog_revision_id", { value: "cat_4", reason: "Canary for rev 4" }),
    ).toEqual({
      kind: "spacecraft_override",
      action: "update",
      entity_id: "sc_1",
      changes: [{ path: "catalog_revision_id", value: { value: "cat_4", reason: "Canary for rev 4" } }],
    });
    expect(overrideOp("sc_1", "frame_parameters.frame_size", null).changes).toEqual([
      { path: "frame_parameters/frame_size", value: null },
    ]);
  });

  it("lists overridable fields, Catalog revision first", () => {
    expect(overridableFields({ sections }).map((o) => `${o.section}:${o.field.path}`)).toEqual([
      "Catalog:catalog_revision_id",
      "Framing:frame_parameters.frame_size",
    ]);
  });

  it("requires a value in the override form", () => {
    expect(overrideSchemaField(field("frame_parameters.frame_size", "TM frame length"))).toMatchObject({
      path: "frame_parameters.frame_size",
      required: true,
    });
  });
});
