import { formatShort } from "@/ui";
import type { DirectoryRow } from "./api.ts";

/**
 * The directory row's words, shared by the desktop table and the phone rows. null is unknown: the
 * table shows "—", a phone row drops the part (ux Dashboards.md › Phone).
 */
export function spacecraftText(row: DirectoryRow): string | null {
  const s = row.spacecraft;
  if (s === undefined) return null;
  if (s === null) return "No widgets";
  switch (s.mode) {
    case "fixed":
      return s.spacecraft?.name ?? "One spacecraft";
    case "context":
      return "Chosen when viewing";
    case "fleet":
      return "Whole fleet";
    case "mixed":
      return "Mixed";
  }
}

export const updatedText = (row: DirectoryRow): string | null =>
  row.updated_at
    ? `${formatShort(new Date(row.updated_at))}${row.updated_by?.name ? ` · ${row.updated_by.name}` : ""}`
    : null;

export const spacecraftWord = (row: DirectoryRow) => spacecraftText(row) ?? "—";
export const updatedWord = (row: DirectoryRow) => updatedText(row) ?? "—";
