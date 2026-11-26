import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  spacecraftRef,
  type ApiResult,
  type Decoded,
  dashboardId as dashboardIdReader,
} from "@/api";

/**
 * Directory endpoints (plans/dashboards.md "D1–D4, D6", api-ops): list, star, archive/restore,
 * create, duplicate, record a view. Invalidation: `dashboards`.
 */

const person = d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) }));
const spacecraftSummary = d.nullable(
  d.variant("mode", {
    fixed: d.object({
      mode: d.literal("fixed"),
      spacecraft: d.nullable(spacecraftRef),
    }),
    context: d.object({ mode: d.literal("context") }),
    fleet: d.object({ mode: d.literal("fleet") }),
    mixed: d.object({ mode: d.literal("mixed") }),
  }),
);
const row = d.object({
  id: dashboardIdReader,
  name: d.string,
  description: d.nullable(d.string),
  tags: d.array(d.string, 64),
  archived: d.boolean,
  starred: d.boolean,
  current_version: d.nullable(d.integer),
  updated_at: d.nullable(d.timestamp),
  updated_by: person,
  viewed_at: d.nullable(d.timestamp),
  /** Optional until api-ops ships the derivation; absent reads as unknown. */
  spacecraft: d.optional(spacecraftSummary),
});
export type DirectoryRow = Decoded<typeof row>;

const listing = d.object({
  dashboards: d.array(row, 200),
  available_tags: d.array(d.string, 512),
  total: d.integer,
  page: d.integer,
  pages: d.integer,
  page_size: d.integer,
  can_create: d.boolean,
  shortcuts: d.object({ starred: d.array(row, 50), recent: d.array(row, 50) }),
});
export type Directory = Decoded<typeof listing>;

export const sorts = ["updated", "name", "name_desc"] as const;
export type DirectoryQuery = Readonly<{
  q: string;
  tags: readonly string[];
  starred: boolean;
  archived: boolean;
  sort: (typeof sorts)[number];
  page: number;
}>;

const root = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/dashboards`;
const one = (missionId: MissionId, id: string) => `${root(missionId)}/${encodeURIComponent(id)}`;
const nothing = d.nullable((value) => value);

export function fetchDirectory(
  missionId: MissionId,
  query: DirectoryQuery,
  signal?: AbortSignal,
): Promise<ApiResult<Directory>> {
  const p = new URLSearchParams({ sort: query.sort, page: String(query.page) });
  if (query.q) p.set("q", query.q);
  if (query.tags.length) p.set("tags", query.tags.join(","));
  if (query.starred) p.set("starred", "true");
  if (query.archived) p.set("archived", "true");
  return request(`${root(missionId)}?${p.toString()}`, listing, signal ? { signal } : {});
}

export const setStarred = (missionId: MissionId, id: string, starred: boolean) =>
  request(`${one(missionId, id)}/star`, nothing, { method: starred ? "PUT" : "DELETE" });

// Archive (D3) lives once, in settings/api.ts (`archiveDashboard`), shared with Settings › General.
export const unarchive = (missionId: MissionId, id: string) =>
  request(`${one(missionId, id)}/restore`, nothing, { method: "POST", body: {} });

const created = d.object({ id: d.token, version: d.integer });
export type NewSpacecraft =
  | { mode: "fixed"; spacecraft_id: string }
  | { mode: "context" }
  | { mode: "fleet" };
/** D4: `spacecraft` fixed sets the default scope (76ff5edc); context and fleet set none. */
export const createDashboard = (
  missionId: MissionId,
  input: Readonly<{
    name: string;
    description: string;
    tags: readonly string[];
    spacecraft: NewSpacecraft;
  }>,
) =>
  request(root(missionId), created, {
    method: "POST",
    body: {
      name: input.name,
      // The server takes a string ("" for none); null is refused (qa, 422 on field name).
      description: input.description,
      tags: input.tags,
      spacecraft: input.spacecraft,
    },
  });
export const duplicate = (missionId: MissionId, id: string, name: string) =>
  request(`${one(missionId, id)}/duplicate`, created, { method: "POST", body: { name } });

/** D6: feeds "recent"; fired once per viewer open. Failures don't matter to the viewer. */
export const recordView = (missionId: MissionId, id: string) =>
  request(`${one(missionId, id)}/views`, nothing, { method: "POST", body: {} });
