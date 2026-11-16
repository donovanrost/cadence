import { formatClock } from "@/ui";
import { shownValue } from "@/features/commands/groups/resolved.ts";
import type { Reservation } from "./records.ts";

/** ux U74: a store or provider code in sentence case ('release_pending' → 'Release pending'). */
export function sentenceCase(code: string): string {
  const words = code.replaceAll("_", " ").trim().toLowerCase();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : code;
}

export const clock = (iso: string) => `${formatClock(new Date(iso))}Z`;

/** '02:59:40–03:08:52Z' (U74 revision rows). */
export const span = (from: string | null, to: string | null) =>
  from && to ? `${formatClock(new Date(from))}–${clock(to)}` : "no window";

type ValueRow = Reservation["values"][number];
export type ValueCell = Readonly<{
  text: string;
  /** ux U74 (C2's rule): differs from Requested = weight 600; equal or missing = text-4. */
  tone: "base" | "differs" | "same" | "missing" | "withheld";
  title?: string | undefined;
}>;

const WITHHELD_TITLE = "Structured or over 512 bytes; Cadence doesn't display it.";

/** One provider field's three cells (Requested, Confirmed, Accepted). */
export function valueCells(row: ValueRow): [ValueCell, ValueCell, ValueCell] {
  const cell = (json: string | null, compare: boolean): ValueCell => {
    if (row.restricted && json === null)
      return { text: "Not shown", tone: "withheld", title: WITHHELD_TITLE };
    if (json === null) return { text: "not set", tone: "missing" };
    if (!compare) return { text: shownValue(json), tone: "base" };
    return { text: shownValue(json), tone: json === row.requested_json ? "same" : "differs" };
  };
  return [
    cell(row.requested_json, false),
    cell(row.confirmed_json, true),
    cell(row.accepted_json, true),
  ];
}

/** 'Northlight · v4'; ids with versions elsewhere ('plan_… · v3'). */
export const withVersion = (label: string, version: number | null) =>
  version === null ? label : `${label} · v${version}`;

/** The cell's look (ux U74). */
export const TONE_CLASS: Readonly<Record<ValueCell["tone"], string>> = {
  base: "text-text-2",
  differs: "font-semibold text-readout",
  same: "text-text-4",
  missing: "text-text-4",
  withheld: "text-text-4 italic",
};
