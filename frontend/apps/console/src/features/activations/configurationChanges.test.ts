import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import {
  changeCounts,
  changesHeading,
  firstStartLine,
  groupHeading,
  namesLine,
  noChangesLine,
  orderedGroups,
  rowLine,
  showAllLabel,
  summaryLines,
  telemetryOffLine,
  unshownCount,
  valueWord,
} from "./changesWords.ts";
import {
  configurationChangesField,
  configurationChangesReader,
  groupNamesReader,
  type ChangeRow,
} from "./configurationChanges.ts";

const craft = (n: number) => ({
  spacecraft_id: `sc_${n}`,
  name: `EARENDIL-${String(n).padStart(3, "0")}`,
});
const crafts = (from: number, count: number) =>
  Array.from({ length: Math.min(count, 100) }, (_, i) => craft(from + i));

const catalogRow = {
  field: "catalog_revision",
  label: "Catalog revision",
  before: { id: "cr_13", number: 13 },
  after: { id: "cr_14", number: 14 },
};
const apidsRow = {
  field: "handled_apids",
  label: "Decoded APIDs",
  before: [1, 2],
  after: [1, 2, 3],
};

const group = (o: Record<string, unknown>) => ({
  rows: [],
  first_start: false,
  telemetry_enabled: true,
  count: 1,
  spacecraft: [craft(1)],
  ...o,
});

/** A 312-craft rollout: 288 change the catalog, 12 also the APIDs, 12 unchanged; 5 are new and 3 have telemetry off. */
const fleetWire = {
  groups: [
    group({ rows: [catalogRow], count: 283, spacecraft: crafts(1, 283) }),
    group({ rows: [], count: 12, spacecraft: crafts(300, 12) }),
    group({ rows: [catalogRow, apidsRow], count: 12, spacecraft: crafts(400, 12) }),
    group({
      rows: [{ ...catalogRow, before: null }],
      first_start: true,
      count: 2,
      spacecraft: crafts(500, 2),
    }),
    group({
      rows: [{ ...catalogRow, before: null }],
      first_start: true,
      telemetry_enabled: false,
      count: 3,
      spacecraft: crafts(510, 3),
    }),
  ],
  total: 312,
};

const read = (wire: unknown) => configurationChangesReader(wire);
const rowOf = (wire: Record<string, unknown>): ChangeRow => {
  const row = read({ groups: [group({ rows: [wire] })], total: 1 }).groups.items[0]?.rows.items[0];
  if (!row) throw new Error("row didn't decode");
  return row;
};

afterEach(() => vi.restoreAllMocks());

describe("#235 what a spacecraft configuration request changes", () => {
  it("is optional on the detail until api ships it, and null for other kinds", () => {
    const field = configurationChangesField.configuration_changes;
    expect(field(undefined)).toBeUndefined();
    expect(field(null)).toBeNull();
    expect(field(fleetWire)?.total).toBe(312);
  });

  it("sums the summary from the groups' counts, exactly", () => {
    const c = read(fleetWire);
    expect(changeCounts(c)).toEqual({
      changed: 300,
      unchanged: 12,
      firstStart: 5,
      telemetryOff: 3,
      fields: [
        { field: "catalog_revision", count: 300 },
        { field: "handled_apids", count: 12 },
      ],
    });
    expect(changesHeading(c)).toBe("What changes · 312 spacecraft");
    expect(summaryLines(c)).toEqual([
      "300 spacecraft change: Catalog revision (300), Decoded APIDs (12).",
      "12 have no changes.",
      "5 start for the first time.",
    ]);
    expect(telemetryOffLine(c)?.text).toBe(
      "Telemetry is off for 3 of the 312 spacecraft, so once this is active they start but decode nothing: no live values, alarms or history. Turn telemetry on with a change set first.",
    );
  });

  it("puts the no-change group last and words each group", () => {
    const c = read(fleetWire);
    const [first, , , , last] = orderedGroups(c);
    if (!first || !last) throw new Error("groups missing");
    expect(last.rows.items).toEqual([]);
    expect(groupHeading(first)).toBe("283 spacecraft");
    expect(namesLine(first)).toBe("EARENDIL-001, EARENDIL-002, EARENDIL-003 and 280 more");
    expect(showAllLabel(first)).toBe("Show all 283");
    expect(noChangesLine(last, true)).toBe(
      "No changes on 12 spacecraft: EARENDIL-300, EARENDIL-301, EARENDIL-302 and 9 more.",
    );
    expect(firstStartLine(first)).toBe(
      "Nothing is active for these spacecraft yet, so every setting is new.",
    );
  });

  it("reads one craft as U94's single panel", () => {
    const c = read({ groups: [group({ rows: [catalogRow], telemetry_enabled: false })], total: 1 });
    const [g] = c.groups.items;
    if (!g) throw new Error("group missing");
    expect(changesHeading(c)).toBe("What changes");
    expect(groupHeading(g)).toBe("EARENDIL-001");
    expect(namesLine(g)).toBe("EARENDIL-001");
    expect(showAllLabel(g)).toBeNull();
    expect(noChangesLine(g, false)).toBe(
      "Nothing changes for EARENDIL-001: this configuration matches what's active.",
    );
    expect(firstStartLine(g)).toBe(
      "Nothing is active for EARENDIL-001 yet, so every setting is new.",
    );
    expect(telemetryOffLine(c)?.text).toMatch(
      /^Telemetry is off for EARENDIL-001, so once this is active it starts but decodes nothing/,
    );
  });

  it("words every value as U94 has it, never an id", () => {
    expect(rowLine(rowOf(catalogRow), false)).toBe(
      "Catalog revision: catalog rev 13 → catalog rev 14",
    );
    expect(rowLine(rowOf({ ...catalogRow, before: null }), true)).toBe(
      "Catalog revision: catalog rev 14",
    );
    const noNumber = rowOf({ ...catalogRow, after: { id: "cr_14", number: null } });
    expect(valueWord(noNumber, "after")).toBe("a catalog revision");
    const source = rowOf({
      field: "telemetry_source",
      label: "x",
      before: null,
      after: { id: "src_1", name: "X-band RX" },
    });
    expect(rowLine(source, false)).toBe("Packet source: Not set → X-band RX");
    const apids = rowOf({ ...apidsRow, before: [], after: [1, 2, 3, 4, 5, 6, 7, 8, 9] });
    expect(rowLine(apids, false)).toBe("Decoded APIDs: None → 9 APIDs");
    expect(valueWord(rowOf(apidsRow), "after")).toBe("0x01, 0x02, 0x03");
    const frame = rowOf({ field: "frame_size", label: "x", before: 1115, after: 1 });
    expect(rowLine(frame, false)).toBe("Frame size: 1,115 bytes → 1 byte");
    const trunc = rowOf({
      field: "truncated_primary_header",
      label: "x",
      before: false,
      after: true,
    });
    expect(rowLine(trunc, false)).toBe("Truncated primary header: No → Yes");
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const down = rowOf({ field: "downlink", label: "x", before: "tm", after: "newlink" });
    expect(rowLine(down, false)).toBe("Downlink protocol: TM → newlink");
  });

  it("counts what it can't show, never dropping it silently", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const c = read({
      groups: [
        group({ rows: [catalogRow, { field: "new_field", label: "New", before: 1, after: 2 }] }),
        { rows: [], count: "many" },
      ],
      total: 2,
    });
    expect(c.groups.items[0]?.rows.items).toHaveLength(1);
    expect(unshownCount(c)).toBe(2);
    expect(warn).toHaveBeenCalledTimes(2);
  });

  it("never states counts as exact when a group can't be read (dashboards' review, ux #235)", () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const unreadable = { rows: [], telemetry_enabled: false, count: "twelve" };
    const allOn = read({
      groups: [group({ rows: [catalogRow], count: 300, spacecraft: crafts(1, 300) }), unreadable],
      total: 312,
    });
    expect(summaryLines(allOn)).toContain(
      "These counts cover 300 of the 312 spacecraft. This console can't show what changes for the other 12.",
    );
    expect(telemetryOffLine(allOn)).toEqual({
      tone: "caution",
      text: "This console can't show whether telemetry is on for 12 of the 312 spacecraft.",
    });
    const someOff = read({
      groups: [
        group({ rows: [catalogRow], count: 297, spacecraft: crafts(1, 297) }),
        group({
          rows: [catalogRow],
          telemetry_enabled: false,
          count: 3,
          spacecraft: crafts(400, 3),
        }),
        unreadable,
      ],
      total: 312,
    });
    const off = telemetryOffLine(someOff);
    expect(off?.tone).toBe("crit");
    expect(off?.text).toMatch(/^Telemetry is off for 3 of the 312 spacecraft/);
    expect(off?.text).toMatch(/ This console can't show whether it's on for the other 12\.$/);
  });

  it("reads a page of a group's names", () => {
    expect(groupNamesReader({ spacecraft: crafts(101, 100), next_offset: 200 }).next_offset).toBe(
      200,
    );
    expect(groupNamesReader({ spacecraft: [craft(1)], next_offset: null }).spacecraft).toHaveLength(
      1,
    );
  });
});
