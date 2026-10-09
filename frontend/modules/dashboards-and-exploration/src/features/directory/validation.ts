import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import {
  directorySorts,
  type DashboardRow,
  type DirectoryModel,
  type DirectoryOutcome,
  type DirectoryPage,
} from "./contracts";

const fail = (): never => {
  throw Error("Invalid dashboard directory data");
};
export const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : fail();
const exact = (value: unknown, keys: readonly string[]) => {
  const r = record(value);
  const actual = Object.keys(r);
  return actual.length === keys.length && keys.every((key) => key in r) ? r : fail();
};
const integer = (value: unknown, minimum = 0): number =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= minimum ? value : fail();
const text = (value: unknown, max = 512): string =>
  typeof value === "string" && value.length <= max ? value : fail();
const nullableText = (value: unknown, max = 512) => (value === null ? null : text(value, max));
const id = (value: unknown): string => {
  const result = text(value, 256);
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  return result && !/[\u0000-\u001f]/.test(result) ? result : fail();
};
const timestamp = (value: unknown) =>
  value === null ? null : Number.isNaN(Date.parse(text(value, 64))) ? fail() : text(value, 64);
const bool = (value: unknown): boolean => (typeof value === "boolean" ? value : fail());
const list = <T>(value: unknown, read: (item: unknown) => T, max: number): T[] =>
  Array.isArray(value) && value.length <= max ? value.map(read) : fail();
const unique = <T>(values: T[], key: (item: T) => unknown = (item) => item): T[] =>
  new Set(values.map(key)).size === values.length ? values : fail();

const rowKeys = [
  "id",
  "name",
  "description",
  "tags",
  "archived",
  "starred",
  "version",
  "updated_at",
  "updated_by",
  "viewed_at",
] as const;

function readRow(value: unknown): DashboardRow {
  const r = exact(value, rowKeys);
  return {
    id: id(r.id),
    name: text(r.name),
    description: nullableText(r.description, 4096),
    tags: unique(list(r.tags, (tag) => text(tag), 100)),
    archived: bool(r.archived),
    starred: bool(r.starred),
    version: r.version === null ? null : integer(r.version, 1),
    updated_at: timestamp(r.updated_at),
    updated_by: nullableText(r.updated_by),
    viewed_at: timestamp(r.viewed_at),
  };
}

const rows = (value: unknown, max: number) => unique(list(value, readRow, max), (row) => row.id);

export function readModel(value: unknown, mission: string): DirectoryModel {
  const m = exact(value, [
    "version",
    "mission_id",
    "author",
    "filters",
    "available_tags",
    "total",
    "pages",
    "page_size",
    "rows",
    "shortcuts",
  ]);
  if (m.version !== 2 || !mission || m.mission_id !== mission || m.page_size !== 50) fail();
  const f = exact(m.filters, ["query", "tags", "starred", "archived", "sort", "page"]);
  const s = exact(m.shortcuts, ["starred", "recent"]);
  const total = integer(m.total);
  const pages = integer(m.pages, 1);
  const page = integer(f.page, 1);
  const listed = rows(m.rows, 50);
  if (
    pages !== Math.max(1, Math.ceil(total / 50)) ||
    page > pages ||
    listed.length !== Math.min(50, Math.max(0, total - (page - 1) * 50))
  )
    fail();
  const sort = directorySorts.find((option) => option === f.sort) ?? fail();
  return {
    version: 2,
    mission_id: mission,
    author: bool(m.author),
    filters: {
      query: text(f.query),
      tags: unique(list(f.tags, (tag) => text(tag), 10)),
      starred: bool(f.starred),
      archived: bool(f.archived),
      sort,
      page,
    },
    available_tags: unique(list(m.available_tags, (tag) => text(tag), 2000)),
    total,
    pages,
    page_size: 50,
    rows: listed,
    shortcuts: { starred: rows(s.starred, 500), recent: rows(s.recent, 5) },
  };
}

export function readDirectoryPage(value: unknown, context: OpsPageContext): DirectoryPage {
  if (context.resourceId !== undefined) fail();
  const r = exact(value, ["model", "sequence"]);
  return { model: readModel(r.model, context.missionId), sequence: integer(r.sequence) };
}

export function readOutcome(value: unknown, context: OpsPageContext): DirectoryOutcome {
  const r = record(value);
  const envelope = record(r.page ?? {});
  const page = envelope.status === "ready" ? readDirectoryPage(envelope.data, context) : null;
  switch (r.status) {
    case "ok": {
      const result = record(r.result ?? {});
      return page
        ? { status: "ok", page, result: { dashboard_id: id(result.dashboard_id) } }
        : fail();
    }
    case "invalid":
      return { status: "invalid", code: text(r.code ?? "invalid_input", 64), page };
    case "forbidden":
    case "rejected":
    case "unknown":
      return { status: r.status, page };
    default:
      return fail();
  }
}
