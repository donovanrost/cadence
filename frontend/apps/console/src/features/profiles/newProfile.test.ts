import { describe, expect, it } from "vite-plus/test";
import { createOp, duplicateForm } from "./newProfile.ts";

const field = (path: string, label: string, value: unknown) => ({
  path,
  label,
  type: "integer" as const,
  unit: null,
  enum: null,
  range: null,
  default: null,
  overridable: true,
  runtime_impact: "none" as const,
  help: null,
  value,
  overridden_by: 0,
});

const source = {
  sections: [
    {
      key: "framing",
      label: "Framing",
      fields: [field("frame_parameters.frame_size", "TM frame length", 1115)],
    },
    { key: "limits", label: "Limits", fields: [field("limits.x", "X", 3)] },
  ],
  applications: { hk: { rate: 1 } },
  rules: [
    {
      id: "r1",
      label: "TT&C",
      name_template: "{sc}-ttc",
      enabled: true,
      stations: [{ id: "gs1", code: "SVB", name: "Svalbard", transport_id: null }],
      legs: [{ direction: "downlink" as const, role: "primary" as const }],
      route_count: 3,
      samples: [],
    },
  ],
};

describe("Duplicate as new profile", () => {
  it("prefills the editable sections, not limits, and carries rules and app settings", () => {
    const form = duplicateForm(source);
    expect(form.schema.fields.map((f) => f.path)).toEqual(["frame_parameters.frame_size"]);
    expect(form.values).toEqual({ "frame_parameters.frame_size": "1115" });
    expect(form.carried["applications"]).toEqual({ hk: { rate: 1 } });
    expect(form.carried["routing_rules"]).toEqual([
      {
        label: "TT&C",
        name_template: "{sc}-ttc",
        enabled: true,
        stations: [{ ground_station_id: "gs1", transport_id: null }],
        legs: [{ direction: "downlink", role: "primary" }],
      },
    ]);
  });
  it("stages one create with the name and nested field values", () => {
    expect(
      createOp(" Block 2 ", { applications: {} }, [
        { path: "frame_parameters.frame_size", value: 1115 },
        { path: "downlink_protocol", value: "tm" },
      ]),
    ).toEqual({
      kind: "spacecraft_profile",
      action: "create",
      document: {
        applications: {},
        display_name: "Block 2",
        frame_parameters: { frame_size: 1115 },
        downlink_protocol: "tm",
      },
    });
  });
});
