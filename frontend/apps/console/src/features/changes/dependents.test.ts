import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { dependents } from "./dependents.ts";

/** Fixture: domain 5504322a8, the derived_point_in_use HOLD (ux U42). */
describe("derived points a retire would break (U42)", () => {
  it("lists each dependent once, from the HOLD's details", () => {
    const hold = {
      kind: "derived_telemetry",
      entity_id: "dd_soc",
      reason: "derived_point_in_use",
      blocking: true,
      sentence: "DERIVED.SOC can't be retired: DERIVED.HEALTH's expression uses it. …",
      details: {
        point_id: "DERIVED.SOC",
        used_by: [{ point_id: "DERIVED.HEALTH", name: "Battery health", definition_id: "dd_h" }],
      },
    };
    const r = decode(previewReader, {
      verdict: "hold",
      checks: [
        { key: "compatibility", verdict: "hold", blocking: true, items: [hold, hold] },
        // Other holds send details of their own shape; they don't break the read.
        {
          key: "other",
          verdict: "hold",
          items: [{ kind: "spacecraft", reason: "x", details: "not an object" }],
        },
      ],
      effects: [],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    expect(dependents(r.value)).toEqual([{ point_id: "DERIVED.HEALTH", definition_id: "dd_h" }]);
  });
});
