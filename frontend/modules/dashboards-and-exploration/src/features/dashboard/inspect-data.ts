import type { WorkspaceField, WorkspacePlacement } from "../workspace/contracts";
import { frameRows, primaryFrames } from "./widget-data";

export type FieldStats = {
  key: string;
  name: string;
  unit: string | null;
  count: number;
  min: number | null;
  max: number | null;
  mean: number | null;
  last: number | null;
};

export function fieldStats(placement: WorkspacePlacement): FieldStats[] {
  return primaryFrames(placement).flatMap((frame, frameIndex) =>
    frame.fields
      .filter((field) => field.kind === "number")
      .map((field) => {
        const numbers = field.values.filter((v): v is number => typeof v === "number");
        const sum = numbers.reduce((total, v) => total + v, 0);
        return {
          key: `${frameIndex}:${field.name}`,
          name: field.name,
          unit: field.unit,
          count: numbers.length,
          min: numbers.length ? Math.min(...numbers) : null,
          max: numbers.length ? Math.max(...numbers) : null,
          mean: numbers.length ? sum / numbers.length : null,
          last: numbers.at(-1) ?? null,
        };
      }),
  );
}

export type InspectTable = { columns: WorkspaceField[]; rows: string[][]; truncated: boolean };

const cell = (value: WorkspaceField["values"][number] | undefined, field: WorkspaceField) =>
  value === null || value === undefined
    ? ""
    : field.kind === "time" && typeof value === "number"
      ? new Date(value).toISOString()
      : String(value);

/** All primary frames as one table; columns are the union of field names. */
export function inspectTable(placement: WorkspacePlacement, limit = 500): InspectTable {
  const frames = primaryFrames(placement);
  const columns = Array.from(
    new Map(frames.flatMap((f) => f.fields.map((field) => [field.name, field] as const))).values(),
  );
  const all = frames.flatMap((frame) =>
    frameRows(frame).map((row) => columns.map((field) => cell(row[field.name], field))),
  );
  return { columns, rows: all.slice(-limit).reverse(), truncated: all.length > limit };
}

export function toCsv(placement: WorkspacePlacement): string {
  const table = inspectTable(placement, Number.MAX_SAFE_INTEGER);
  const quote = (value: string) =>
    /[",\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
  const header = table.columns.map((c) => quote(c.unit ? `${c.name} (${c.unit})` : c.name));
  return [header, ...[...table.rows].reverse().map((row) => row.map(quote))]
    .map((line) => line.join(","))
    .join("\n");
}
