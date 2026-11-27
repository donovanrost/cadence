import {
  actor,
  decoders as d,
  request,
  requestPage,
  requestPageMeta,
  scid,
  spacecraftId,
  stationId,
  type ApiResult,
  type Decoded,
  type MissionId,
  type Page,
  type SpacecraftId,
} from "@/api";

/**
 * A spacecraft's orbit (#895, slice 6 of #732). Contracts: docs/apogee/api/element-sets.md and
 * docs/apogee/api/predicted-passes.md. No flight dynamics here: the console reads what the server
 * stored and predicted.
 */
export const elementSetFormats = ["tle", "omm"] as const;
export const elementSetSources = ["manual", "api"] as const;

export const elementSetReader = d.object({
  id: d.token,
  format: d.known(elementSetFormats),
  source: d.known(elementSetSources),
  epoch: d.timestamp,
  // free-text: the catalog's own object name, shown as written (null when the message has none).
  object_name: d.nullable(d.string),
  norad_id: d.nullable(d.integer),
  element_set_number: d.nullable(d.integer),
  received_at: d.timestamp,
  created_by: d.nullable(actor),
});
export type ElementSet = Decoded<typeof elementSetReader>;

const path = (m: MissionId, sc: SpacecraftId, rest: string) =>
  `/missions/${encodeURIComponent(m)}/spacecraft/${encodeURIComponent(sc)}/${rest}`;

export type OrbitKey = Readonly<{ missionId: MissionId; spacecraftId: SpacecraftId }>;

/** The newest epoch, or null: the honest no-orbit-yet state. */
export function fetchCurrentElementSet(
  key: OrbitKey,
  signal: AbortSignal,
): Promise<ApiResult<ElementSet | null>> {
  return request(
    path(key.missionId, key.spacecraftId, "element-sets/current"),
    d.nullable(elementSetReader),
    { signal },
  );
}

/** The history, newest epoch first, for `usePagedQuery`. */
export async function fetchElementSetPage(
  key: OrbitKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<ElementSet, undefined>>> {
  const params = new URLSearchParams({ limit: "25" });
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPage(
    path(key.missionId, key.spacecraftId, `element-sets?${params.toString()}`),
    d.array(elementSetReader, 200),
    { signal },
  );
  if (!r.ok) return r;
  return { ok: true, value: { items: r.value.value, next: r.value.nextCursor, meta: undefined } };
}

export const predictedPassReader = d.object({
  id: d.token,
  aos: d.timestamp,
  tca: d.timestamp,
  los: d.timestamp,
  max_elevation_deg: d.number,
  spacecraft: d.object({ id: spacecraftId, name: d.string, scid: d.nullable(scid) }),
  station: d.object({
    id: stationId,
    // free-text: the station's name as the mission wrote it (null when the station is gone).
    display_name: d.nullable(d.string),
    // free-text: the station's short code, an identifier (null when the station is gone).
    code: d.nullable(d.string),
  }),
  element_set: d.object({ id: d.token, epoch: d.timestamp }),
});
export type PredictedPass = Decoded<typeof predictedPassReader>;

/** What every page repeats, so an empty or partial week says why (predicted-passes.md §Coverage). */
export const coverageReader = d.object({
  coverage: d.object({
    horizon_end: d.nullable(d.timestamp),
    computed_at: d.nullable(d.timestamp),
    unpredicted: d.object({
      spacecraft_without_element_set: d.integer,
      spacecraft_deep_space: d.integer,
      stations_without_location: d.integer,
      passes_not_bracketed: d.integer,
    }),
  }),
});
export type Coverage = Decoded<typeof coverageReader>["coverage"];

/**
 * The window a list reads, fixed per key so later pages read the same one: from now to now + 14
 * days, the most a spacecraft's window may span. The server holds passes only up to its horizon
 * (7 days by default), so the list ends there on its own: it is everything predicted, never
 * partial (#964 review).
 */
export type PassesKey = OrbitKey & Readonly<{ from: string; to: string }>;

export const PASS_WINDOW_MS = 14 * 86_400_000;

export function passesKey(key: OrbitKey, now: Date): PassesKey {
  return {
    ...key,
    from: now.toISOString(),
    to: new Date(now.getTime() + PASS_WINDOW_MS).toISOString(),
  };
}

/** One page of the spacecraft's predicted passes in its window, AOS first, for `usePagedQuery`. */
export async function fetchPredictedPassPage(
  key: PassesKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<PredictedPass, Coverage>>> {
  const params = new URLSearchParams({ from: key.from, to: key.to, limit: "100" });
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPageMeta(
    path(key.missionId, key.spacecraftId, `predicted-passes?${params.toString()}`),
    d.array(predictedPassReader, 500),
    coverageReader,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value, next: r.value.nextCursor, meta: r.value.meta.coverage },
  };
}
