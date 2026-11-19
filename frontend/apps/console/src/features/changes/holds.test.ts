import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { alarmPoints, appHolds, checkTitle, modelHolds, whyPlaceholder } from "./holds.ts";
import { blockingReason } from "./itemLines.ts";

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

describe("telemetry_app_not_installed (U63, domain e587668da)", () => {
  const hold = {
    kind: "spacecraft",
    entity_id: "sc_1",
    spacecraft_ids: ["sc_1", "sc_2", "sc_3", "sc_4"],
    reason: "telemetry_app_not_installed",
    blocking: true,
    sentence:
      "Telemetry can't be turned on for 4 spacecraft: the telemetry app isn't installed on them. Install the app in Setup › Apps first.",
    details: { app_key: "telemetry_decom", app_name: "Telemetry decom" },
  };

  it("blocks Apply with the server's sentence and links to the app's page", () => {
    const p = preview([hold]);
    expect(blockingReason(p)).toBe(`Can't apply yet: ${hold.sentence}`);
    expect(appHolds(p)).toEqual([
      {
        appKey: "telemetry_decom",
        appName: "Telemetry decom",
        spacecraftIds: ["sc_1", "sc_2", "sc_3", "sc_4"],
      },
    ]);
  });

  it("titles a check that holds only this reason, and not a mixed one", () => {
    const p = preview([hold]);
    expect(checkTitle(p.checks[0]?.items ?? [])).toBe("Telemetry app not installed");
    const mixed = preview([hold, alarm]);
    expect(checkTitle(mixed.checks[0]?.items ?? [])).toBeNull();
  });

  it("links nothing without an app key", () => {
    expect(appHolds(preview([{ ...hold, details: {} }]))).toEqual([]);
  });
});

describe("mission_model_not_approved (U65, domain's gate)", () => {
  const hold = (rev: string, number: number | null) => ({
    kind: "catalog_compatibility",
    entity_id: "sc_1",
    reason: "mission_model_not_approved",
    blocking: true,
    sentence:
      "Catalog rev 4 isn't approved yet, so 499 spacecraft can't move to it. An org admin approves it in Setup › Catalog first.",
    spacecraft_ids: ["sc_1", "sc_2"],
    details: {
      catalog_database_id: "db-1",
      catalog_revision_id: "cr-4",
      catalog_revision_number: number,
      mission_model_revision_id: rev,
    },
  });

  it("titles the check and links each revision once ('Open rev 4')", () => {
    const p = preview([hold("mm-4", 4), hold("mm-4", 4), hold("mm-5", null)]);
    expect(checkTitle(p.checks[0]?.items ?? [])).toBe("Catalog revision not approved");
    expect(modelHolds(p)).toEqual([
      { revisionId: "mm-4", catalogRevisionNumber: 4 },
      { revisionId: "mm-5", catalogRevisionNumber: null },
    ]);
    expect(blockingReason(p)).toBe(
      "Can't apply yet: Catalog rev 4 isn't approved yet, so 499 spacecraft can't move to it. An org admin approves it in Setup › Catalog first.",
    );
  });

  it("reads an unknown reason as a diagnostic, not a failure", () => {
    const p = preview([{ kind: "limit_definition", entity_id: "x", reason: "brand_new_reason" }]);
    expect(p.checks[0]?.items[0]?.reason).toEqual({ unrecognized: "brand_new_reason" });
    expect(modelHolds(p)).toEqual([]);
  });
});

describe("scid_shared_in_organization (U81 §1, domain fbc2ae00c)", () => {
  const scid = (mission: object | null, missionCount: number) => ({
    kind: "spacecraft",
    entity_id: "sc-new",
    op_id: null,
    change_id: null,
    reason: "scid_shared_in_organization",
    blocking: false,
    sentence: "Another mission in this organization also flies SCID 42 through KSAT. …",
    details: {
      scid: 42,
      provider_accounts: [
        { id: "acct-ksat", name: "KSAT" },
        { id: "acct-2", name: null },
      ],
      mission,
      mission_count: missionCount,
    },
  });

  it("decodes all four details keys, a null mission and an unnamed account", () => {
    const [item] = preview([scid(null, 2)]).checks[0]?.items ?? [];
    expect(item?.reason).toBe("scid_shared_in_organization");
    expect(item?.details).toMatchObject({
      scid: 42,
      provider_accounts: [
        { id: "acct-ksat", name: "KSAT" },
        { id: "acct-2", name: null },
      ],
      mission: null,
      mission_count: 2,
    });
    const named = preview([scid({ id: "m-b", name: "Bravo" }, 1)]).checks[0]?.items[0];
    expect(named?.details?.mission).toEqual({ id: "m-b", name: "Bravo" });
  });

  it("says 'both' for one other mission, named or folded, and 'these' for two or more", () => {
    const both = "Why it's safe for both spacecraft to use SCID 42";
    expect(whyPlaceholder(preview([scid({ id: "m-b", name: "Bravo" }, 1)]))).toBe(both);
    expect(whyPlaceholder(preview([scid(null, 1)]))).toBe(both);
    expect(whyPlaceholder(preview([scid(null, 3)]))).toBe(
      "Why it's safe for these spacecraft to share SCID 42",
    );
  });

  it("keeps the general placeholder for two or more holds", () => {
    expect(whyPlaceholder(preview([scid({ id: "m-b", name: "Bravo" }, 1), scid(null, 2)]))).toBe(
      "Why it's safe to apply despite these holds",
    );
  });
});
