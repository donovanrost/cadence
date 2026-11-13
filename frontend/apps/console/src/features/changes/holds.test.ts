import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { alarmPoints, whyPlaceholder } from "./holds.ts";

/** Fixtures: ux U43 (limits HOLD) and U40 (archive HOLDs); domain's details {point_id, …}. */
function preview(items: readonly object[], action: "update" | "delete" = "update") {
  const r = decode(previewReader, {
    verdict: items.length > 0 ? "hold" : "go",
    diffs: [{ kind: "limit_definition", entity_id: "ld_1", action }],
    checks: [{ key: "compatibility", verdict: items.length > 0 ? "hold" : "go", items }],
    effects: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
const alarm = {
  kind: "limit_definition",
  entity_id: "ld_1",
  reason: "limit_alarm_active",
  sentence: "EPS.VBAT has a red-limit alarm raised now. …",
  details: { point_id: "EPS.VBAT", limit_set_name: "DEFAULT", severity: "red", episode_id: "e1" },
};

describe("acknowledgeable HOLDs (U40, U43)", () => {
  it("names what to justify for one HOLD, by what the change does", () => {
    expect(whyPlaceholder(preview([alarm]))).toBe("Why it's safe to change them while it's raised");
    expect(whyPlaceholder(preview([alarm], "delete"))).toBe("Why it's safe to clear it");
    expect(
      whyPlaceholder(preview([{ kind: "spacecraft", reason: "spacecraft_passes_booked" }])),
    ).toBe("Why the passes stay booked");
  });

  it("uses one placeholder for several, and none without HOLDs or for a blocking one", () => {
    const booked = { kind: "spacecraft", reason: "spacecraft_passes_booked" };
    expect(whyPlaceholder(preview([alarm, booked]))).toBe(
      "Why it's safe to apply despite these holds",
    );
    expect(whyPlaceholder(preview([]))).toBeNull();
    expect(
      whyPlaceholder(
        preview([{ kind: "spacecraft", reason: "spacecraft_commands_waiting", blocking: true }]),
      ),
    ).toBeNull();
  });

  it("lists each alarmed point once for 'Open in Alarms'", () => {
    expect(alarmPoints(preview([alarm, alarm]))).toEqual(["EPS.VBAT"]);
  });
});
