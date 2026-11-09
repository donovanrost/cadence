/**
 * Manifest CSV import (AddSpacecraft.md step 01). Parses RFC 4180 CSV, maps columns to fields by
 * header name, and reads each row into typed cells with per-cell problems. Nothing is coerced:
 * a cell that isn't a valid value is reported, not defaulted.
 */

export const manifestFields = ["name", "scid", "norad", "plane", "slot", "profile"] as const;
export type ManifestField = (typeof manifestFields)[number];

export const fieldLabels: Readonly<Record<ManifestField, string>> = {
  name: "Name",
  scid: "SCID",
  norad: "NORAD id",
  plane: "Plane",
  slot: "Slot",
  profile: "Profile",
};

const synonyms: Readonly<Record<ManifestField, readonly string[]>> = {
  name: ["name", "spacecraft", "spacecraft_name", "display_name"],
  scid: ["scid", "spacecraft_id", "sc_id"],
  norad: ["norad", "norad_id", "norad_cat_id", "catnr"],
  plane: ["plane", "orbit_plane"],
  slot: ["slot", "orbit_slot"],
  profile: ["profile", "spacecraft_profile", "profile_name"],
};

export const MAX_MANIFEST_ROWS = 2000;

export type CsvResult =
  | Readonly<{ ok: true; header: readonly string[]; rows: readonly (readonly string[])[] }>
  | Readonly<{ ok: false; message: string }>;

/** RFC 4180: quoted fields, doubled quotes, CRLF or LF. Blank lines are skipped. */
export function parseCsv(text: string): CsvResult {
  const records: string[][] = [];
  let field = "";
  let record: string[] = [];
  let quoted = false;
  let i = 0;
  const source = text.replace(/^﻿/, "");
  const endRecord = () => {
    record.push(field);
    if (!(record.length === 1 && record[0] === "")) records.push(record);
    record = [];
    field = "";
  };
  while (i < source.length) {
    const ch = source[i];
    if (quoted) {
      if (ch === '"' && source[i + 1] === '"') {
        field += '"';
        i += 2;
        continue;
      }
      if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"' && field === "") quoted = true;
    else if (ch === ",") {
      record.push(field);
      field = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && source[i + 1] === "\n") i += 1;
      endRecord();
    } else field += ch;
    i += 1;
  }
  if (quoted) return { ok: false, message: "The file ends inside a quoted value." };
  if (field !== "" || record.length > 0) endRecord();
  const [header, ...rows] = records;
  if (!header) return { ok: false, message: "The file is empty." };
  if (rows.length === 0) return { ok: false, message: "The file has a header but no rows." };
  if (rows.length > MAX_MANIFEST_ROWS)
    return { ok: false, message: `At most ${MAX_MANIFEST_ROWS} rows per manifest.` };
  return { ok: true, header: header.map((h) => h.trim()), rows };
}

/** Column index per field, or null when unmapped. */
export type ColumnMapping = Readonly<Record<ManifestField, number | null>>;

export function guessMapping(header: readonly string[]): ColumnMapping {
  const normalized = header.map((h) => h.toLowerCase().replace(/[\s-]+/g, "_"));
  const find = (field: ManifestField) => {
    const index = normalized.findIndex((h) => synonyms[field].includes(h));
    return index === -1 ? null : index;
  };
  return {
    name: find("name"),
    scid: find("scid"),
    norad: find("norad"),
    plane: find("plane"),
    slot: find("slot"),
    profile: find("profile"),
  };
}

export type CellProblem = Readonly<{ field: ManifestField; message: string }>;

export type ManifestRow = Readonly<{
  line: number;
  name: string | null;
  scid: number | null;
  norad: number | null;
  plane: number | null;
  slot: number | null;
  profile: string | null;
  problems: readonly CellProblem[];
}>;

const bounds: Readonly<Record<"scid" | "norad" | "plane" | "slot", readonly [number, number]>> = {
  scid: [0, 1023],
  norad: [1, 999_999_999],
  plane: [0, 999],
  slot: [0, 9999],
};

export function readRows(
  header: readonly string[],
  rows: readonly (readonly string[])[],
  mapping: ColumnMapping,
): readonly ManifestRow[] {
  return rows.map((cells, index) => {
    const problems: CellProblem[] = [];
    const text = (field: ManifestField): string | null => {
      const column = mapping[field];
      if (column === null) return null;
      const value = (cells[column] ?? "").trim();
      return value === "" ? null : value;
    };
    const int = (field: "scid" | "norad" | "plane" | "slot"): number | null => {
      const value = text(field);
      if (value === null) return null;
      const [min, max] = bounds[field];
      if (!/^\d+$/.test(value) || Number(value) < min || Number(value) > max) {
        problems.push({ field, message: `${fieldLabels[field]} “${value}” is not ${min}–${max}` });
        return null;
      }
      return Number(value);
    };
    if (cells.length !== header.length)
      problems.push({
        field: "name",
        message: `Row has ${cells.length} of ${header.length} columns`,
      });
    const row = {
      line: index + 2,
      name: text("name"),
      scid: int("scid"),
      norad: int("norad"),
      plane: int("plane"),
      slot: int("slot"),
      profile: text("profile"),
    };
    if (row.name === null && mapping.name !== null)
      problems.push({ field: "name", message: "Name is empty" });
    return { ...row, problems };
  });
}

export function manifestTemplate(): string {
  return `${manifestFields.join(",")}\nEXAMPLE-001,501,,11,1,\n`;
}
