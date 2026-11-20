import { isKnown } from "@/api/index.ts";
import { formatCount, plural, type OpState } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { apidHex } from "./words.ts";

/** #595b (U94, U65, U102; mms-ux): the catalog revision picker's words. */

type CatalogRow = ConfigurationSnapshot["catalogs"][number];

/** "catalog rev 14 · EARENDIL FSW · FSW 2.4" (U65's number first; without it, name and label). */
export const catalogRowTitle = (c: CatalogRow) =>
  c.number !== undefined
    ? `catalog rev ${c.number} · ${c.name} · ${c.label}`
    : `${c.name} · ${c.label}`;

/** "812 declarations · 40 packets · 120 commands" */
export const catalogCounts = (c: CatalogRow) =>
  [
    `${formatCount(c.declarations)} ${c.declarations === 1 ? "declaration" : "declarations"}`,
    plural(c.packets, "packet"),
    plural(c.commands, "command"),
  ].join(" · ");

export type RowState = Readonly<{
  choosable: boolean;
  tag: Readonly<{ label: string; state: OpState }> | null;
  /** The muted line under the counts; null when there's nothing to say. */
  line: string | null;
  /** A status the console doesn't know, for Technical details (U20). */
  technical: string | null;
}>;

/**
 * mms-ux: a revision not yet approved can be chosen (a draft can hold it) but is WAITING;
 * rejected, withdrawn and retired can't be chosen; an unknown status can't either. No status
 * (an older server): choosable, untagged, as before. The active one is tagged ACTIVE.
 */
export function rowState(c: CatalogRow, activeId: string | null): RowState {
  const active = c.id === activeId ? { label: "Active", state: "nominal" as const } : null;
  const s = c.approval_status;
  if (s === undefined || s === "approved")
    return { choosable: true, tag: active, line: null, technical: null };
  if (!isKnown(s))
    return { choosable: false, tag: active, line: "Can't be chosen.", technical: s.unrecognized };
  if (s === "candidate")
    return {
      choosable: true,
      tag: active ?? { label: "Waiting", state: "caution" },
      line: "Not approved yet. The draft can be saved, but not sent until it's approved.",
      technical: null,
    };
  const line = {
    rejected: "Rejected, so spacecraft can't move to it.",
    withdrawn: "Its approval was withdrawn.",
    retired: "Retired.",
  }[s];
  return { choosable: false, tag: active, line, technical: null };
}

/** U94: why Change… is off when the profile sets the catalog revision. */
export const profileSetsLine = (craft: string) =>
  `${craft}'s profile sets its catalog revision. Change it on the profile, through Setup › Changes.`;

/**
 * mms-ux: "Catalog rev 15 doesn't define 0x101 and 0x1A0, so they're removed from Handled APIDs.
 * Discard edits brings them back." Up to 5 APIDs, then "and N more" (U40).
 */
export function droppedApidsLine(rev: string, dropped: readonly number[]): string | null {
  if (dropped.length === 0) return null;
  const shown = dropped.slice(0, 5).map(apidHex);
  const more = dropped.length - shown.length;
  const list =
    more > 0
      ? `${shown.join(", ")} and ${more} more`
      : shown.length === 1
        ? (shown[0] ?? "")
        : `${shown.slice(0, -1).join(", ")} and ${shown.at(-1) ?? ""}`;
  const Rev = `${rev.charAt(0).toUpperCase()}${rev.slice(1)}`;
  const one = dropped.length === 1;
  // mms-ux on #628: one APID reads "it's … brings it back".
  return `${Rev} doesn't define ${list}, so ${one ? "it's" : "they're"} removed from Handled APIDs. Discard edits brings ${one ? "it" : "them"} back.`;
}
