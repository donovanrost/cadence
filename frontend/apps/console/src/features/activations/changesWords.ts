import { vocabularyText } from "@/api/index.ts";
import { formatCount, plural } from "@/ui";
import type {
  ChangeField,
  ChangeGroup,
  ChangeRow,
  ConfigurationChanges,
} from "./configurationChanges.ts";
import { changeFields } from "./configurationChanges.ts";

/** ux U94 (#235): the What changes panel's words. Values are never ids (U25). */
export const FIELD_LABELS: Readonly<Record<ChangeField, string>> = {
  catalog_revision: "Catalog revision",
  telemetry_source: "Packet source",
  handled_apids: "Decoded APIDs",
  downlink: "Downlink protocol",
  uplink: "Uplink protocol",
  frame_size: "Frame size",
  secondary_header_length: "Secondary header",
  insert_zone_length: "Insert zone",
  ocf_length: "OCF",
  truncated_primary_header: "Truncated primary header",
};

const LINK = { tm: "TM", aos: "AOS", uslp: "USLP", tc: "TC" } as const;
const NOT_SET = "Not set";
/** Names a group's line lists before "and N more". */
export const NAMES_LISTED = 3;

const hex = (apid: number) => `0x${apid.toString(16).toUpperCase().padStart(2, "0")}`;

/** One side of a row in U94's words: "catalog rev 14", "0x01, 0x02", "1,115 bytes", "Yes". */
export function valueWord(row: ChangeRow, side: "before" | "after"): string {
  switch (row.field) {
    case "catalog_revision": {
      const v = row[side];
      if (!v) return NOT_SET;
      return v.number === null ? "a catalog revision" : `catalog rev ${v.number}`;
    }
    case "telemetry_source":
      return row[side]?.name ?? NOT_SET;
    case "handled_apids": {
      const v = row[side];
      if (!v) return NOT_SET;
      if (v.length === 0) return "None";
      return v.length <= 8 ? v.map(hex).join(", ") : plural(v.length, "APID");
    }
    case "downlink":
    case "uplink": {
      const v = row[side];
      return v === null ? NOT_SET : vocabularyText(v, LINK);
    }
    case "frame_size":
    case "secondary_header_length":
    case "insert_zone_length":
    case "ocf_length": {
      const v = row[side];
      return v === null ? NOT_SET : plural(v, "byte");
    }
    case "truncated_primary_header": {
      const v = row[side];
      if (v === null) return NOT_SET;
      return v ? "Yes" : "No";
    }
  }
}

/** "Catalog revision: catalog rev 13 → catalog rev 14"; a first start shows only the new value. */
export function rowLine(row: ChangeRow, firstStart: boolean): string {
  const label = FIELD_LABELS[row.field];
  const after = valueWord(row, "after");
  return firstStart ? `${label}: ${after}` : `${label}: ${valueWord(row, "before")} → ${after}`;
}

/** Rows the console couldn't read in a group, plus groups it couldn't read at all. */
export const unshownCount = (c: ConfigurationChanges) =>
  c.groups.unshown.length + c.groups.items.reduce((n, g) => n + g.rows.unshown.length, 0);

const isUnchanged = (g: ChangeGroup) => g.rows.items.length === 0 && g.rows.unshown.length === 0;

/** Changed groups in api's order, then the no-change group (U94). */
export const orderedGroups = (c: ConfigurationChanges): readonly ChangeGroup[] => [
  ...c.groups.items.filter((g) => !isUnchanged(g)),
  ...c.groups.items.filter(isUnchanged),
];

const sum = (groups: readonly ChangeGroup[], keep: (g: ChangeGroup) => boolean) =>
  groups.filter(keep).reduce((n, g) => n + g.count, 0);

/** The summary's counts, from the groups' counts (exact: api computes the groups). */
export function changeCounts(c: ConfigurationChanges) {
  const groups = c.groups.items;
  return {
    changed: sum(groups, (g) => !isUnchanged(g)),
    unchanged: sum(groups, isUnchanged),
    firstStart: sum(groups, (g) => g.first_start),
    telemetryOff: sum(groups, (g) => !g.telemetry_enabled),
    fields: changeFields.flatMap((field) => {
      const count = sum(groups, (g) => g.rows.items.some((r) => r.field === field));
      return count > 0 ? [{ field, count }] : [];
    }),
  };
}

/** One craft reads as U94's single-craft panel; a fleet gets the summary and group headings. */
export const isFleet = (c: ConfigurationChanges) => c.total !== 1;

/** "What changes · 312 spacecraft"; one craft: "What changes". */
export const changesHeading = (c: ConfigurationChanges) =>
  isFleet(c) ? `What changes · ${formatCount(c.total)} spacecraft` : "What changes";

/** U94's summary lines, each only when nonzero (fleets only). */
export function summaryLines(c: ConfigurationChanges): readonly string[] {
  const n = changeCounts(c);
  const lines: string[] = [];
  if (n.changed > 0) {
    const fields = n.fields
      .map((f) => `${FIELD_LABELS[f.field]} (${formatCount(f.count)})`)
      .join(", ");
    const verb = n.changed === 1 ? "changes" : "change";
    lines.push(`${formatCount(n.changed)} spacecraft ${verb}: ${fields}.`);
  }
  if (n.unchanged > 0)
    lines.push(`${formatCount(n.unchanged)} ${n.unchanged === 1 ? "has" : "have"} no changes.`);
  if (n.firstStart > 0)
    lines.push(
      `${formatCount(n.firstStart)} ${n.firstStart === 1 ? "starts" : "start"} for the first time.`,
    );
  return lines;
}

const OFF_TAIL = "no live values, alarms or history. Turn telemetry on with a change set first.";

/** U94's crit telemetry-off line (it warns, it doesn't block); null while telemetry is on. */
export function telemetryOffLine(c: ConfigurationChanges): string | null {
  const off = changeCounts(c).telemetryOff;
  if (off === 0) return null;
  if (!isFleet(c)) {
    const name = c.groups.items[0]?.spacecraft[0]?.name ?? "this spacecraft";
    return `Telemetry is off for ${name}, so once this is active it starts but decodes nothing: ${OFF_TAIL}`;
  }
  const they = off === 1 ? "it starts but decodes" : "they start but decode";
  return `Telemetry is off for ${formatCount(off)} of the ${formatCount(c.total)} spacecraft, so once this is active ${they} nothing: ${OFF_TAIL}`;
}

/** A group's heading: "300 spacecraft", or the craft's name for a group of one. */
export const groupHeading = (g: ChangeGroup) =>
  g.count === 1 && g.spacecraft[0] ? g.spacecraft[0].name : `${formatCount(g.count)} spacecraft`;

/** "EARENDIL-001, EARENDIL-002, EARENDIL-003 and 297 more"; all names when there are few. */
export function namesLine(g: ChangeGroup): string {
  const names = g.spacecraft.map((s) => s.name);
  if (g.count <= NAMES_LISTED && names.length === g.count) {
    if (names.length <= 1) return names.join("");
    return `${names.slice(0, -1).join(", ")} and ${names.at(-1) ?? ""}`;
  }
  const listed = names.slice(0, NAMES_LISTED);
  return `${listed.join(", ")} and ${formatCount(g.count - listed.length)} more`;
}

/** `Show all 300`, when the line doesn't list every name; null otherwise. */
export const showAllLabel = (g: ChangeGroup) =>
  g.count > NAMES_LISTED ? `Show all ${formatCount(g.count)}` : null;

/** U90/U94's first-start line, for a group of one or many. */
export const firstStartLine = (g: ChangeGroup) =>
  g.count === 1 && g.spacecraft[0]
    ? `Nothing is active for ${g.spacecraft[0].name} yet, so every setting is new.`
    : "Nothing is active for these spacecraft yet, so every setting is new.";

/** The rows-[] group: "No changes on 12 spacecraft: EARENDIL-010, EARENDIL-011 and 10 more." */
export const noChangesLine = (g: ChangeGroup) =>
  `No changes on ${formatCount(g.count)} spacecraft: ${namesLine(g)}.`;
