import { vocabularyText } from "@/api/index.ts";
import { formatCount, plural } from "@/ui";
import type {
  ChangeField,
  ChangeGroup,
  ChangeRow,
  ConfigurationChanges,
} from "./configurationChanges.ts";
import {
  changeFields,
  craftInSentence,
  craftName,
  UNKNOWN_SOURCE,
} from "./configurationChanges.ts";
import { compositionInSentence, isComposed } from "@/features/catalog/composition.ts";

/** ux U94 (#235): the What changes panel's words. Values are never ids (U25). */
export const FIELD_LABELS: Readonly<Record<ChangeField, string>> = {
  catalog_revision: "Catalog revision",
  telemetry_source: "Packet source",
  handled_apids: "Handled APIDs",
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
      // U109: a composed side reads "composition 3" ("Catalog revision: catalog rev 14 → composition 3").
      if (isComposed(v.composition)) return compositionInSentence(v.composition);
      return v.number === null ? "a catalog revision" : `catalog rev ${v.number}`;
    }
    case "telemetry_source": {
      const v = row[side];
      return v ? (v.name ?? UNKNOWN_SOURCE) : NOT_SET;
    }
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

/** Rows the console couldn't read, across every group it could. */
export const unshownRows = (c: ConfigurationChanges) =>
  c.groups.items.flatMap((g) => g.rows.unshown);

/** Rows the console couldn't read in a group, plus groups it couldn't read at all. */
export const unshownCount = (c: ConfigurationChanges) =>
  c.groups.unshown.length + unshownRows(c).length;

/** ux #235: Approve stays off while any change can't be shown (Reject stays on). */
export const APPROVE_UNSHOWN =
  "Part of what changes can't be shown in this console, so it can't be approved here. Reload to try again. If it's still missing, tell the team that runs Cadence for you, or reject it.";

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
  const unseen = unseenCraft(c);
  // ux (#235): with an unreadable group the counts aren't the whole request; say so.
  if (unseen > 0)
    lines.push(
      `These counts cover ${formatCount(c.total - unseen)} of the ${formatCount(c.total)} spacecraft. This console can't show what changes for the other ${formatCount(unseen)}.`,
    );
  return lines;
}

const OFF_TAIL = "no live values, alarms or history. Turn telemetry on with a change set first.";

/**
 * Craft in groups this console couldn't read: their count is unknown to it, so it's the total less
 * every readable group's count (dashboards' #227 review: never infer the rest).
 */
export function unseenCraft(c: ConfigurationChanges): number {
  if (c.groups.unshown.length === 0) return 0;
  return Math.max(c.total - sum(c.groups.items, () => true), 0);
}

/**
 * U94's telemetry-off line (it warns, it doesn't block): crit when craft are known to be off.
 * ux (#235): craft in unreadable groups aren't known either way, so they're named as unknown, and
 * on their own the line is a caution, never crit. null when every craft is known to be on.
 */
export function telemetryOffLine(
  c: ConfigurationChanges,
): Readonly<{ tone: "crit" | "caution"; text: string }> | null {
  const off = changeCounts(c).telemetryOff;
  const unseen = unseenCraft(c);
  const total = formatCount(c.total);
  if (off === 0)
    return unseen === 0
      ? null
      : {
          tone: "caution",
          text: `This console can't show whether telemetry is on for ${formatCount(unseen)} of the ${total} spacecraft.`,
        };
  const they = off === 1 ? "it starts but decodes" : "they start but decode";
  const line = isFleet(c)
    ? `Telemetry is off for ${formatCount(off)} of the ${total} spacecraft, so once this is active ${they} nothing: ${OFF_TAIL}`
    : `Telemetry is off for ${c.groups.items[0]?.spacecraft[0] ? craftInSentence(c.groups.items[0].spacecraft[0]) : "this spacecraft"}, so once this is active it starts but decodes nothing: ${OFF_TAIL}`;
  const unknown =
    unseen === 0
      ? ""
      : ` This console can't show whether it's on for the other ${formatCount(unseen)}.`;
  return { tone: "crit", text: `${line}${unknown}` };
}

/** A group's heading: "300 spacecraft", or the craft's name for a group of one. */
export const groupHeading = (g: ChangeGroup) =>
  g.count === 1 && g.spacecraft[0]
    ? craftName(g.spacecraft[0])
    : `${formatCount(g.count)} spacecraft`;

/** "EARENDIL-001, EARENDIL-002, EARENDIL-003 and 297 more"; all names when there are few. */
export function namesLine(g: ChangeGroup): string {
  const names = g.spacecraft.map(craftName);
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
    ? `Nothing is active for ${craftInSentence(g.spacecraft[0])} yet, so every setting is new.`
    : "Nothing is active for these spacecraft yet, so every setting is new.";

/**
 * The rows-[] group: "No changes on 12 spacecraft: EARENDIL-010, EARENDIL-011, EARENDIL-012 and 9
 * more."; one craft on its own (ux #235): "Nothing changes for EARENDIL-004: this configuration
 * matches what's active."
 */
export const noChangesLine = (g: ChangeGroup, fleet: boolean) =>
  !fleet && g.spacecraft[0]
    ? `Nothing changes for ${craftInSentence(g.spacecraft[0])}: this configuration matches what's active.`
    : `No changes on ${formatCount(g.count)} spacecraft: ${namesLine(g)}.`;

/**
 * ux U94 (#416): the ids of packet sources the server couldn't name, for Technical details only
 * (the row reads "Unknown packet source"; U25, never an id in the copy).
 */
export function unnamedSourceIds(g: ChangeGroup): string[] {
  const ids = new Set<string>();
  for (const row of g.rows.items) {
    if (row.field !== "telemetry_source") continue;
    for (const v of [row.before, row.after]) if (v && v.name === null) ids.add(v.id);
  }
  return [...ids];
}
