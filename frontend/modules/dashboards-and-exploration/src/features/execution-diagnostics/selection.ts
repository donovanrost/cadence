import { collectionIds, type CollectionId, type DiagnosticRow } from "./contracts";

/** View state only. Changing a selection must not execute a new inspection. */
export type DiagnosticSelection = { collection: CollectionId; row: string | null; filter: string };
export const initialSelection = (): DiagnosticSelection => ({
  collection: "plan",
  row: null,
  filter: "",
});
export function readSelection(value: unknown): DiagnosticSelection {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid diagnostic selection");
  const selection = value as Record<string, unknown>;
  if (
    Object.keys(selection).length !== 3 ||
    ["collection", "row", "filter"].some((key) => !Object.hasOwn(selection, key)) ||
    !collectionIds.includes(selection.collection as CollectionId) ||
    !(
      selection.row === null ||
      (typeof selection.row === "string" &&
        selection.row.length === 64 &&
        /^[a-f0-9]{64}$/.test(selection.row))
    ) ||
    typeof selection.filter !== "string" ||
    /[\u0000-\u001f\u007f]/.test(selection.filter) ||
    new TextEncoder().encode(selection.filter).length > 256
  )
    throw Error("Invalid diagnostic selection");
  return value as DiagnosticSelection;
}
export function matchingRows(rows: DiagnosticRow[], filter: string): DiagnosticRow[] {
  const search = filter.trim().toLowerCase();
  return rows.filter((row) =>
    [row.identity, row.title, row.status, ...row.details.map((detail) => detail.value)].some(
      (value) => value !== null && String(value).toLowerCase().includes(search),
    ),
  );
}
export const collectionLabels: Record<CollectionId, string> = {
  plan: "Plan",
  requests: "Requests",
  frames: "Frames",
  cache: "Cache",
  source_execution: "Source execution",
  refresh: "Refresh",
  invalidation: "Invalidation",
};
