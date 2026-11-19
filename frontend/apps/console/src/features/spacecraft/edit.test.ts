import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader, schemaFieldReader } from "@/features/changes/index.ts";
import { detailReader, type SpacecraftDetail } from "./detail.ts";
import {
  archiveHolds,
  archiveOp,
  archiveStaged,
  pairProfile,
  spacecraftDocument,
  withPinnedProfile,
} from "./edit.ts";
import {
  offConsequence,
  operationRows,
  stagedSwitch,
  switchHelp,
  switchOp,
  switchSummary,
} from "./operation.ts";

/** Fixtures: api setup.md "Spacecraft edits" (8243895f1). */
function detail(extra: Record<string, unknown> = {}): SpacecraftDetail {
  const r = decode(detailReader, {
    spacecraft: {
      id: "sc-1",
      name: "EARENDIL-312",
      scid: 312,
      norad_id: null,
      plane: 13,
      slot: 12,
      last_received_at: null,
    },
    profile: { id: "p-1", name: "Block 1", version: 3, latest_version: 4 },
    configuration: null,
    routing_rules: [],
    readiness: { ready: true, checks: [] },
    ...extra,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

function profileField(options: readonly { value: string; label: string }[]) {
  const r = decode(schemaFieldReader, {
    path: "spacecraft_type_id",
    label: "Profile",
    type: "enum",
    unit: null,
    enum: options,
    range: null,
    default: null,
    required: false,
    help: null,
    visible_when: null,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

describe("spacecraft edits (L17)", () => {
  it("prefills from the detail; the switches are the Operation panel's, not the form's (#309)", () => {
    expect(
      spacecraftDocument(detail({ commanding_enabled: true, telemetry_enabled: null })),
    ).toEqual({
      display_name: "EARENDIL-312",
      scid: 312,
      spacecraft_type_id: "p-1",
      spacecraft_type_version: 3,
    });
    const field = (path: string) => ({ ...profileField([]), path });
    const schema = {
      kind: "spacecraft",
      fields: [field("display_name"), field("commanding_enabled"), field("telemetry_enabled")],
    };
    expect(withPinnedProfile(detail({ profile: null }))(schema).fields.map((f) => f.path)).toEqual([
      "display_name",
    ]);
  });

  it("stages a version change with its profile; leaves other changes alone", () => {
    const pair = pairProfile(detail());
    expect(pair([{ path: "spacecraft_type_version", value: 4 }])).toEqual([
      { path: "spacecraft_type_id", value: "p-1" },
      { path: "spacecraft_type_version", value: 4 },
    ]);
    expect(pair([{ path: "display_name", value: "E-312" }])).toEqual([
      { path: "display_name", value: "E-312" },
    ]);
  });

  it("keeps an inactive pinned profile choosable", () => {
    const active = {
      kind: "spacecraft",
      fields: [profileField([{ value: "p-2", label: "Block 2" }])],
    };
    expect(withPinnedProfile(detail())(active).fields[0]?.enum).toEqual([
      { value: "p-2", label: "Block 2" },
      { value: "p-1", label: "Block 1 (inactive)" },
    ]);
    const listed = {
      kind: "spacecraft",
      fields: [profileField([{ value: "p-1", label: "Block 1" }])],
    };
    expect(withPinnedProfile(detail())(listed)).toEqual(listed);
  });

  it("reads the archive holds for this spacecraft only", () => {
    const item = (entity_id: string, reason: string, blocking: boolean) => ({
      kind: "spacecraft",
      entity_id,
      reason,
      blocking,
      sentence: `${reason} ${entity_id}`,
    });
    const r = decode(previewReader, {
      verdict: "hold",
      checks: [
        {
          key: "compatibility",
          verdict: "hold",
          items: [
            item("sc-2", "spacecraft_commands_waiting", true),
            item("sc-1", "spacecraft_passes_booked", false),
          ],
        },
      ],
      effects: [],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    const holds = archiveHolds(r.value, "sc-1");
    expect(holds.waiting).toBeNull();
    expect(holds.booked?.sentence).toBe("spacecraft_passes_booked sc-1");
    expect(archiveOp(detail())).toEqual({
      kind: "spacecraft",
      action: "delete",
      entity_id: "sc-1",
    });
  });

  it("knows an archive is already staged, so it isn't staged twice (qa 11-13)", () => {
    const op = { kind: "spacecraft", action: "delete", entity_id: "sc-1" };
    const set = (state: string) => ({ changes: [{ state, ops: [op] }] });
    expect(archiveStaged(set("staged"), "sc-1")).toBe(true);
    expect(archiveStaged(set("withdrawn"), "sc-1")).toBe(false);
    expect(archiveStaged(set("staged"), "sc-2")).toBe(false);
    expect(archiveStaged(null, "sc-1")).toBe(false);
  });

  it("says what each switch does now (U40)", () => {
    const rows = operationRows(detail({ commanding_enabled: false, telemetry_enabled: true }));
    expect(rows.map((r) => r.sentence)).toEqual([
      "No new requests or releases for EARENDIL-312.",
      "Cadence decodes telemetry from EARENDIL-312.",
    ]);
    const field = { ...profileField([]), path: "commanding_enabled", help: "Lets operators…" };
    expect(switchHelp({ kind: "spacecraft", fields: [field] }, "commanding_enabled")).toBe(
      "Lets operators…",
    );
    expect(switchHelp(null, "telemetry_enabled")).toBeNull();
    const unset = operationRows(detail())[0];
    expect(unset?.on).toBeNull();
    expect(unset?.sentence).toBe(
      "No active configuration covers EARENDIL-312 yet, so this isn't set.",
    );
  });
});

describe("U40 switches on the Operation panel (#309)", () => {
  it("words the Changes line and what turning off stops", () => {
    expect(switchSummary("EARENDIL-312", "commanding_enabled", false)).toBe(
      "EARENDIL-312 · turn commanding off",
    );
    expect(switchSummary("EARENDIL-312", "telemetry_enabled", true)).toBe(
      "EARENDIL-312 · turn telemetry on",
    );
    expect(offConsequence("EARENDIL-312", "commanding_enabled")).toBe(
      "Turning commanding off stops new requests and releases for EARENDIL-312.",
    );
    expect(offConsequence("EARENDIL-312", "telemetry_enabled")).toBe(
      "No live values, alarms or new history from EARENDIL-312 until it's turned on again.",
    );
  });

  it("stages the spacecraft kind's switch path, and reads the staged target from the open set", () => {
    expect(switchOp("sc-1", "commanding_enabled", false)).toEqual({
      kind: "spacecraft",
      action: "update",
      entity_id: "sc-1",
      changes: [{ path: "commanding_enabled", value: false }],
    });
    const set = {
      changes: [
        {
          ops: [
            {
              kind: "spacecraft",
              entity_id: "sc-1",
              paths: ["commanding_enabled"],
              payload: { changes: [{ path: "commanding_enabled", value: false }] },
            },
          ],
        },
      ],
    };
    expect(stagedSwitch(set, "sc-1", "commanding_enabled")).toBe(false);
    expect(stagedSwitch(set, "sc-1", "telemetry_enabled")).toBeNull();
    expect(stagedSwitch(set, "sc-2", "commanding_enabled")).toBeNull();
    expect(stagedSwitch(null, "sc-1", "commanding_enabled")).toBeNull();
  });
});
