import type { OpState } from "@/ui";
import { eventState, eventText, type EpisodeEvent } from "@/features/alarms/index.ts";
import { severityState, type MissionEvent } from "@/features/timeline/index.ts";

/** B2 lines: mission events plus the shown alarm's lifecycle actions, newest first. */
export type LogLine = Readonly<{ key: string; at: string; state: OpState; text: string }>;

/** Lifecycle actions the mission timeline doesn't carry (raised/cleared are already there). */
const LIFECYCLE = new Set<EpisodeEvent["kind"]>([
  "acknowledged",
  "assigned",
  "unassigned",
  "note",
  "handed_off",
]);

export function logLines(
  events: readonly MissionEvent[] | null,
  episodeEvents: readonly EpisodeEvent[] | null,
): LogLine[] {
  const fromMission = (events ?? []).map((e) => ({
    key: e.id,
    at: e.at,
    state: severityState(e.severity),
    text: e.text,
  }));
  // Without the mission read, show the whole episode history rather than nothing.
  const fromEpisode = (episodeEvents ?? [])
    .filter((e) => events === null || LIFECYCLE.has(e.kind))
    .map((e) => ({ key: `episode:${e.id}`, at: e.at, state: eventState(e), text: eventText(e) }));
  return [...fromMission, ...fromEpisode].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
}
