import { decoders as d, request, type ApiResult, type Decoded } from "@/api";

/**
 * Playlists (plans/dashboards-slice6.md D23/D24; DECISIONS #76 Q6 update/delete, Q10 delete =
 * hard delete after a confirm, audited). Present mode has no endpoint: it walks `dashboards`
 * through the viewer's D5. Invalidation: `dashboards`.
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

const detail = d.object({
  playlist: d.object({
    id: d.token,
    name: d.string,
    description: d.nullable(d.string),
    dwell_seconds: d.integer,
    wallboard_mode: d.boolean,
    updated_at: d.nullable(d.timestamp),
    dashboards: d.array(d.object({ id: d.token, name: d.string, archived: d.boolean }), 50),
  }),
});
export type Playlist = Decoded<typeof detail>["playlist"];

export type PlaylistInput = Readonly<{
  name: string;
  description: string;
  dwell_seconds: number;
  wallboard_mode: boolean;
  dashboard_ids: readonly string[];
}>;
/** Server bounds (proposal): name 1–120, dwell 10–3600 s, 1–50 unique dashboards. */
export const DWELL = { min: 10, max: 3600 } as const;
export const MAX_DASHBOARDS = 50;

const root = (missionId: string) =>
  `/missions/${encodeURIComponent(missionId)}/dashboard-playlists`;
const one = (missionId: string, id: string) => `${root(missionId)}/${encodeURIComponent(id)}`;
const created = d.object({ id: d.token });
const nothing = d.nullable((value) => value);

export function fetchPlaylists(
  missionId: string,
  q: string,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof listing>>> {
  const query = q ? `?q=${encodeURIComponent(q)}` : "";
  return request(`${root(missionId)}${query}`, listing, signal ? { signal } : {});
}
export function fetchPlaylist(
  missionId: string,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Playlist>> {
  return request(
    one(missionId, id),
    (v, path) => detail(v, path).playlist,
    signal ? { signal } : {},
  );
}
export const createPlaylist = (missionId: string, body: PlaylistInput) =>
  request(root(missionId), created, {
    method: "POST",
    body: { ...body, description: body.description || null },
  });
export const updatePlaylist = (missionId: string, id: string, body: PlaylistInput) =>
  request(one(missionId, id), created, {
    method: "PATCH",
    body: { ...body, description: body.description || null },
  });
export const deletePlaylist = (missionId: string, id: string) =>
  request(one(missionId, id), nothing, { method: "DELETE" });
