import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  detailsOf,
  isError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
  type Unrecognized,
} from "@/api";

/**
 * Dashboards library (slice 8; proposal plans/dashboards-library.md, D21/D22, DECISIONS #76 Q6/Q10).
 * Reusable widgets: list, one item with versions and where it's used, rename, and delete, which
 * retires (never a hard delete) and is refused while a current dashboard version places it.
 * Invalidation: `dashboards`. Unrouted until the endpoints land; built against fixtures.
 */

export const widgetKinds = [
  "value_tile",
  "time_series",
  "status_matrix",
  "data_table",
  "state_timeline",
  "event_timeline",
  "constellation_health",
] as const;
export type WidgetKind = (typeof widgetKinds)[number];

/**
 * `kind` is the latest version's widget_type_id (api ffd5c6d69), namespaced: `cadence.time_series`.
 * Cadence's own types read without the namespace; another vendor's keeps its full id as the word.
 */
const ownType = (id: string) => (id.startsWith("cadence.") ? id.slice("cadence.".length) : id);
const kindReader: Reader<WidgetKind | Unrecognized> = (value, path = "") =>
  d.knownText(widgetKinds)(ownType(d.string(value, path)), path);

export const KIND_WORDS: Readonly<Record<WidgetKind, string>> = {
  value_tile: "Value tile",
  time_series: "Time series",
  status_matrix: "Status matrix",
  data_table: "Data table",
  state_timeline: "State timeline",
  event_timeline: "Event timeline",
  constellation_health: "Constellation health",
};
/** A kind this console doesn't know reads in words from its key, never as an error. */
/** A definition's widget_type_id in words ("Value tile"); another vendor's id as written. */
export function widgetTypeWord(id: string): string {
  const own = ownType(id);
  const known = widgetKinds.find((k) => k === own);
  return known ? KIND_WORDS[known] : own.replaceAll("_", " ");
}

export const kindWord = (kind: string | Unrecognized): string => {
  const raw = typeof kind === "string" ? kind : kind.unrecognized;
  const known = widgetKinds.find((k) => k === raw);
  return known ? KIND_WORDS[known] : raw.replaceAll("_", " ");
};

const person = d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) }));
const itemReader = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  kind: kindReader,
  latest_version: d.integer,
  updated_at: d.nullable(d.timestamp),
  updated_by: person,
});
const rowReader = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  kind: kindReader,
  latest_version: d.integer,
  used_by_count: d.integer,
  updated_at: d.nullable(d.timestamp),
  updated_by: person,
});
export type LibraryRow = Decoded<typeof rowReader>;

const listReader = d.object({
  items: d.array(rowReader, 200),
  total: d.integer,
  page: d.integer,
  pages: d.integer,
  page_size: d.integer,
  can_edit: d.boolean,
});
export type LibraryList = Decoded<typeof listReader>;

const usedByReader = d.object({
  dashboards: d.array(
    d.object({
      id: d.token,
      name: d.string,
      placements: d.integer,
      pinned_versions: d.optional(d.array(d.integer, 100)),
    }),
    500,
  ),
});
export type UsedBy = Decoded<typeof usedByReader>;

const versionReader = d.object({
  version: d.integer,
  summary: d.nullable(d.string),
  saved_at: d.nullable(d.timestamp),
  saved_by: person,
});
const detailReader = d.object({
  item: itemReader,
  version: d.object({
    version: d.integer,
    definition_json: d.string,
    summary: d.nullable(d.string),
    saved_at: d.nullable(d.timestamp),
    saved_by: person,
  }),
  versions: d.array(versionReader, 100),
  used_by: usedByReader,
  can_edit: d.boolean,
});
export type LibraryDetail = Decoded<typeof detailReader>;
export type LibraryItem = LibraryDetail["item"];

/** A sibling of /dashboards (like /dashboard-playlists), so `library` never reads as a dashboard id. */
const root = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/dashboard-library`;
const one = (missionId: MissionId, id: string) => `${root(missionId)}/${encodeURIComponent(id)}`;
const nothing = d.nullable((value) => value);

export function fetchLibrary(
  missionId: MissionId,
  query: Readonly<{ q: string; page: number }>,
  signal?: AbortSignal,
): Promise<ApiResult<LibraryList>> {
  const p = new URLSearchParams({ page: String(query.page) });
  if (query.q) p.set("q", query.q);
  return request(`${root(missionId)}?${p.toString()}`, listReader, signal ? { signal } : {});
}

export function fetchLibraryItem(
  missionId: MissionId,
  id: string,
  version: number | null,
  signal?: AbortSignal,
): Promise<ApiResult<LibraryDetail>> {
  const q = version === null ? "" : `?version=${version}`;
  return request(`${one(missionId, id)}${q}`, detailReader, signal ? { signal } : {});
}

export function renameItem(
  missionId: MissionId,
  id: string,
  body: Readonly<{
    name: string;
    description: string;
    expected_version: number;
    expected_updated_at: string | null;
  }>,
) {
  return request(one(missionId, id), itemReader, { method: "PATCH", body });
}

/** Retire (Q10). 204 decodes null. Both guards: the version and the row as read (dashboards). */
export function retireItem(
  missionId: MissionId,
  id: string,
  expectedVersion: number,
  expectedUpdatedAt: string | null,
) {
  const q = new URLSearchParams({ expected_version: String(expectedVersion) });
  if (expectedUpdatedAt) q.set("expected_updated_at", expectedUpdatedAt);
  return request(`${one(missionId, id)}?${q.toString()}`, nothing, {
    method: "DELETE",
  });
}

/**
 * `409 library_item_in_use`: the dashboards that place it now. Null for any other error, and for
 * an in-use refusal whose details don't decode (the sheet then shows the error, never "unused").
 */
export function usedByOf(error: ApiError): UsedBy["dashboards"] | null {
  if (!isError(error, "library_item_in_use")) return null;
  return detailsOf(error, d.object({ used_by: usedByReader }))?.used_by.dashboards ?? null;
}

/** "Used in 3 dashboards: A, B, C." (ux Dashboards.md § Library). */
export function usedInWords(dashboards: readonly Readonly<{ name: string }>[]): string {
  const n = dashboards.length;
  if (n === 0) return "Not used in any dashboard.";
  return `Used in ${n === 1 ? "1 dashboard" : `${n} dashboards`}: ${dashboards.map((x) => x.name).join(", ")}.`;
}
