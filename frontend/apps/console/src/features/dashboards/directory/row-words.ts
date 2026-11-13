import { formatShort } from "@/ui";
import type { DirectoryRow } from "./api.ts";

/** The directory row's words, shared by the desktop table and the phone rows. */
export function spacecraftWord(row: DirectoryRow): string {
  const s = row.spacecraft;
  if (s === undefined) return "—";
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

export const updatedWord = (row: DirectoryRow) =>
  row.updated_at
    ? `${formatShort(new Date(row.updated_at))}${row.updated_by?.name ? ` · ${row.updated_by.name}` : ""}`
    : "—";
