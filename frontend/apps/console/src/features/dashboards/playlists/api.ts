import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  detailsOf,
  isError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
} from "@/api";

/**
 * Playlists (api 475cf1295, contract dashboards.md §D23/D24; DECISIONS #76 Q6 update/delete, Q10
 * delete = hard delete after a confirm, audited). Present mode has no endpoint: it walks
 * `dashboards` through the viewer's D5. Invalidation: `dashboards`.
 */
const person = d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) }));
const summary = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  dwell_seconds: d.integer,
  wallboard_mode: d.boolean,
  dashboard_count: d.integer,
  updated_at: d.nullable(d.timestamp),
  updated_by: person,
});
export type PlaylistSummary = Decoded<typeof summary>;
const listing = d.object({ playlists: d.array(summary, 500), can_edit: d.boolean });

const playlist = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  dwell_seconds: d.integer,
  wallboard_mode: d.boolean,
  updated_at: d.nullable(d.timestamp),
  updated_by: person,
  dashboards: d.array(d.object({ id: d.token, name: d.string, archived: d.boolean }), 100),
});
const detail = d.object({ playlist });
export type Playlist = Decoded<typeof playlist>;

export type PlaylistInput = Readonly<{
  name: string;
  description: string;
  dwell_seconds: number;
  wallboard_mode: boolean;
  dashboard_ids: readonly string[];
}>;
/** Domain's bounds (§D24): name 1–120, dwell 5–900 s, 1–100 unique active dashboards. */
export const DWELL = { min: 5, max: 900 } as const;
export const MAX_DASHBOARDS = 100;

const root = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/dashboard-playlists`;
const one = (missionId: MissionId, id: string) => `${root(missionId)}/${encodeURIComponent(id)}`;
const created = d.object({ id: d.token });
const nothing = d.nullable((value) => value);

export function fetchPlaylists(
  missionId: MissionId,
  q: string,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof listing>>> {
  const query = q ? `?q=${encodeURIComponent(q)}` : "";
  return request(`${root(missionId)}${query}`, listing, signal ? { signal } : {});
}
export function fetchPlaylist(
  missionId: MissionId,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Playlist>> {
  return request(
    one(missionId, id),
    (v, path) => detail(v, path).playlist,
    signal ? { signal } : {},
  );
}
export const createPlaylist = (missionId: MissionId, body: PlaylistInput) =>
  request(root(missionId), created, {
    method: "POST",
    body: { ...body, description: body.description || null },
  });
/** `expectedUpdatedAt` is the row's `updated_at` as read; a stale one is 409 version_conflict. */
export const updatePlaylist = (
  missionId: MissionId,
  id: string,
  body: PlaylistInput,
  expectedUpdatedAt: string | null,
) =>
  request(one(missionId, id), created, {
    method: "PATCH",
    body: {
      ...body,
      description: body.description || null,
      expected_updated_at: expectedUpdatedAt,
    },
  });
export const deletePlaylist = (missionId: MissionId, id: string) =>
  request(one(missionId, id), nothing, { method: "DELETE" });

/** 409 version_conflict on a stale PATCH: the playlist as it is now (§D24). */
export const changedPlaylist = (error: ApiError): Playlist | null =>
  isError(error, "version_conflict")
    ? (detailsOf(error, d.object({ current: playlist }))?.current ?? null)
    : null;

/** 422 `details.unknown`: dashboards that aren't active (archived) or aren't this mission's. */
export const refusedDashboards = (error: ApiError): readonly string[] =>
  detailsOf(error, d.object({ unknown: d.array(d.token, 100) }))?.unknown ?? [];

/** 404 playlist_not_found: deleted (present mode, an open sheet). */
export const playlistDeleted = (error: ApiError) => isError(error, "playlist_not_found");
