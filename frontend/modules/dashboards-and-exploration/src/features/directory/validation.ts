import type { DirectoryModel, DirectoryState } from "./contracts";
export const record = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid directory data");
  return value as Record<string, unknown>;
};
export function integer(value: unknown, minimum = 0): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum)
    throw Error("Invalid directory number");
  return value;
}
const text = (value: unknown, max = 512): string => {
  if (typeof value !== "string" || value.length > max) throw Error("Invalid directory text");
  return value;
};
const id = (value: unknown): string => {
  const result = text(value, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  if (!result || /[\u0000-\u001f]/.test(result)) throw Error("Invalid directory identity");
  return result;
};
const bool = (value: unknown): boolean => {
  if (typeof value !== "boolean") throw Error("Invalid directory flag");
  return value;
};
const choice = <T extends string>(value: unknown, choices: readonly T[]): T => {
  if (!choices.includes(value as T)) throw Error("Invalid directory choice");
  return value as T;
};
const list = <T>(value: unknown, read: (v: unknown) => T, max: number): T[] => {
  if (!Array.isArray(value) || value.length > max) throw Error("Invalid directory collection");
  return value.map(read);
};
const unique = (values: string[]) => {
  if (new Set(values).size !== values.length) throw Error("Duplicate directory identity");
  return values;
};
export function readModel(value: unknown, mission: string): DirectoryModel {
  const model = record(value),
    filters = record(model.filters);
  if (model.version !== 1 || model.mission_id !== mission || !mission || model.page_size !== 50)
    throw Error("Wrong directory context");
  const rows = list(
    model.rows,
    (value) => {
      const row = record(value);
      return {
        id: id(row.id),
        name: text(row.name),
        description: row.description === null ? null : text(row.description, 4096),
        tags: unique(list(row.tags, (tag) => text(tag), 100)),
        lifecycle: choice(row.lifecycle, ["active", "archived"] as const),
        starred: bool(row.starred),
        version: integer(row.version, 1),
        published_version:
          row.published_version === null ? null : integer(row.published_version, 1),
        widget_count: integer(row.widget_count),
      };
    },
    50,
  );
  unique(rows.map((row) => row.id));
  const total = integer(model.total),
    pages = integer(model.pages, 1),
    page = integer(filters.page, 1);
  if (
    pages !== Math.max(1, Math.ceil(total / 50)) ||
    page > pages ||
    rows.length !== Math.min(50, Math.max(0, total - (page - 1) * 50))
  )
    throw Error("Invalid directory pagination");
  return {
    version: 1,
    mission_id: mission,
    author: bool(model.author),
    filters: {
      query: text(filters.query),
      lifecycle: choice(filters.lifecycle, ["active", "archived", "all"] as const),
      tag: text(filters.tag),
      sort: choice(filters.sort, ["updated", "name", "widgets"] as const),
      page,
    },
    available_tags: unique(list(model.available_tags, (tag) => text(tag), 2000)),
    total,
    pages,
    page_size: 50,
    rows,
  };
}
export function readDirectory(value: unknown, mission: string): DirectoryState {
  const data = record(value);
  return {
    model: readModel(data.model, mission),
    sequence: integer(data.sequence),
    phase: choice(data.phase, ["editing", "submitted"] as const),
  };
}
