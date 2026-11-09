import {
  decoders as d,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { engineeringValue, thresholdsReader } from "./api.ts";

/** Contract: docs/apogee/api/alarms-console.md (alarm episodes, DECISIONS #6/#17/#22). */

const actor = d.object({ kind: d.token, id: d.nullable(d.token), name: d.nullable(d.string) });

const episodeFields = {
  id: d.token,
  source: d.oneOf(["catalog_monitoring", "ground_limit"] as const),
  status: d.oneOf(["new", "acknowledged", "cleared"] as const),
  cleared_unacknowledged: d.boolean,
  severity: d.oneOf(["critical", "caution"] as const),
  peak_severity: d.oneOf(["critical", "caution"] as const),
  source_state: d.nullable(d.string),
  spacecraft_id: d.nullable(d.token),
  spacecraft: d.nullable(d.object({ id: d.token, name: d.string, scid: d.integer })),
  point: d.object({ id: d.token, name: d.string, unit: d.nullable(d.string) }),
  thresholds: d.nullable(thresholdsReader),
  opened_at: d.timestamp,
  cleared_at: d.nullable(d.timestamp),
  first_value: d.nullable(engineeringValue),
  last_value: d.nullable(engineeringValue),
  last_observed_at: d.nullable(d.timestamp),
  last_evaluated_at: d.nullable(d.timestamp),
  acknowledged_at: d.nullable(d.timestamp),
  acknowledged_by: d.nullable(actor),
  assignee: d.nullable(d.object({ id: d.token, name: d.nullable(d.string) })),
  assigned_at: d.nullable(d.timestamp),
} as const;

const episode = d.object(episodeFields);
export type Episode = Decoded<typeof episode>;

const event = d.object({
  id: d.token,
  kind: d.oneOf([
    "raised",
    "escalated",
    "deescalated",
    "acknowledged",
    "assigned",
    "unassigned",
    "note",
    "handed_off",
    "cleared",
  ] as const),
  actor: d.nullable(actor),
  at: d.timestamp,
  // Kind-specific; read per kind in episodeEventText, never trusted as a whole.
  payload: (value: unknown) => (value !== null && typeof value === "object" ? value : {}),
});
export type EpisodeEvent = Decoded<typeof event>;

const episodeDetail = d.object({ ...episodeFields, events: d.array(event, 2_000) });
export type EpisodeDetail = Decoded<typeof episodeDetail>;

export const ALARM_PERMISSIONS = ["alarm.acknowledge", "alarm.assign"] as const;

export const episodesReader = d.object({
  summary: d.object({ active: d.integer }),
  permissions: d.array(d.token, 20),
  episodes: d.array(episode, 200),
});
export type Episodes = Decoded<typeof episodesReader>;

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/alarm-episodes`;

export function fetchEpisodes(
  missionId: string,
  query: Readonly<{ spacecraftId?: string; state?: "active" | "cleared" | "all" }>,
  signal?: AbortSignal,
): Promise<ApiResult<Episodes>> {
  const params = new URLSearchParams({ state: query.state ?? "active", limit: "200" });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  return request(
    `${base(missionId)}?${params.toString()}`,
    episodesReader,
    signal ? { signal } : {},
  );
}

export function fetchEpisode(missionId: string, episodeId: string, signal?: AbortSignal) {
  return request(
    `${base(missionId)}/${encodeURIComponent(episodeId)}`,
    episodeDetail,
    signal ? { signal } : {},
  );
}

export type EpisodeCommand =
  | Readonly<{ kind: "acknowledge"; note?: string }>
  | Readonly<{ kind: "assign"; userId: string | null; note?: string }>
  | Readonly<{ kind: "hand_off"; to: string | null; note: string }>
  | Readonly<{ kind: "note"; note: string }>;

/**
 * Write outcome (ux U20): `rejected` = the server refused and nothing changed; `unclear` = no
 * readable answer (network, 5xx, malformed), so the change may or may not have happened.
 */
export type CommandOutcome =
  | Readonly<{ status: "done"; episode: EpisodeDetail }>
  | Readonly<{ status: "rejected"; error: ApiError }>
  | Readonly<{ status: "unclear"; error: ApiError }>;

function bodyOf(command: EpisodeCommand): { path: string; body: Record<string, unknown> } {
  const note = "note" in command && command.note?.trim() ? { note: command.note.trim() } : {};
  switch (command.kind) {
    case "acknowledge":
      return { path: "acknowledge", body: note };
    case "assign":
      return { path: "assign", body: { user_id: command.userId, ...note } };
    case "hand_off":
      return { path: "hand-off", body: { to: command.to, note: command.note } };
    case "note":
      return { path: "notes", body: { note: command.note } };
  }
}

export async function runEpisodeCommand(
  missionId: string,
  episodeId: string,
  command: EpisodeCommand,
): Promise<CommandOutcome> {
  const { path, body } = bodyOf(command);
  const result = await request(
    `${base(missionId)}/${encodeURIComponent(episodeId)}/${path}`,
    episodeDetail,
    {
      method: "POST",
      body,
    },
  );
  if (result.ok) return { status: "done", episode: result.value };
  const e = result.error;
  const rejected =
    e.kind === "forbidden" ||
    e.kind === "not_found" ||
    e.kind === "conflict" ||
    e.kind === "invalid" ||
    e.kind === "unauthenticated";
  return rejected ? { status: "rejected", error: e } : { status: "unclear", error: e };
}

/** Assignable people: active members of the mission's organization (setup.md O1). */
const peopleReader = d.object({
  members: d.array(d.object({ user_id: d.token, display_name: d.nullable(d.string) }), 5_000),
});
export type Person = Decoded<typeof peopleReader>["members"][number];

export function fetchPeople(organizationId: string, signal?: AbortSignal) {
  return request(
    `/organizations/${encodeURIComponent(organizationId)}/people`,
    peopleReader,
    signal ? { signal } : {},
  );
}

/** The active episode behind a limit alarm row: same spacecraft and point. */
export function episodeFor(episodes: readonly Episode[], spacecraftId: string, pointId: string) {
  return (
    episodes.find(
      (e) => e.status !== "cleared" && e.spacecraft_id === spacecraftId && e.point.id === pointId,
    ) ?? null
  );
}
