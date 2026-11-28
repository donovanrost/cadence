import type { PointId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { formatClock, type OpState } from "@/ui";
import { eventState, eventText, type EpisodeEvent } from "@/features/alarms/index.ts";
import type { SampleRef } from "./sample/link.ts";
import { severityState, type MissionEvent } from "@/features/timeline/index.ts";

/** B2 lines: mission events plus the shown alarm's lifecycle actions, newest first. */
export type LogLine = Readonly<{
  key: string;
  at: string;
  state: OpState;
  text: string;
  /** ux U71 A7: 'Show sample' for an escalation that carries its sample. */
  sampleTo?: RouteLocationRaw | undefined;
}>;

/** Lifecycle actions the mission timeline doesn't carry (raised/cleared are already there). */
const LIFECYCLE = new Set<EpisodeEvent["kind"]>([
  "acknowledged",
  "assigned",
  "unassigned",
  "note",
  "handed_off",
]);

/** The shown alarm's episode, for its own escalation lines (ux U71 A7). */
export type LogEpisode = Readonly<{
  pointId: PointId;
  openedAt: string;
  clearedAt: string | null;
  events: readonly EpisodeEvent[];
}>;

const at = (iso: string) => `${formatClock(new Date(iso))}Z`;
/** 'Became critical at 02:31:40Z' / 'Eased to caution at …'; null for other kinds. */
function changeText(e: EpisodeEvent): string | null {
  if (!e.sample) return null;
  if (e.kind === "escalated") return `Became critical at ${at(e.sample.at)}`;
  if (e.kind === "deescalated") return `Eased to caution at ${at(e.sample.at)}`;
  return null;
}

/**
 * ux U71 A7: the episode's own escalations replace the timeline's limit lines for that point,
 * only within the episode's span (opened to cleared, or now); outside it they're other episodes.
 */
export function logLines(
  events: readonly MissionEvent[] | null,
  episode: LogEpisode | null,
  sampleTo: (sample: SampleRef) => RouteLocationRaw | null = () => null,
): LogLine[] {
  const changes = (episode?.events ?? []).flatMap((e) => {
    const text = changeText(e);
    const sample = e.sample;
    if (!text || !sample) return [];
    const to = sampleTo(sample);
    return [
      {
        key: `episode:${e.id}`,
        at: e.at,
        state: eventState(e),
        text,
        ...(to ? { sampleTo: to } : {}),
      },
    ];
  });
  const from = episode ? Date.parse(episode.openedAt) : 0;
  const to = episode?.clearedAt ? Date.parse(episode.clearedAt) : Number.POSITIVE_INFINITY;
  const replaced = (e: MissionEvent) =>
    changes.length > 0 &&
    e.kind === "limit" &&
    e.refs.point_id === episode?.pointId &&
    Date.parse(e.at) >= from &&
    Date.parse(e.at) <= to;
  const fromMission = (events ?? [])
    .filter((e) => !replaced(e))
    .map((e) => ({ key: e.id, at: e.at, state: severityState(e.severity), text: e.text }));
  // Without the mission read, show the whole episode history rather than nothing.
  const fromEpisode = (episode?.events ?? [])
    .filter((e) => events === null || LIFECYCLE.has(e.kind))
    .filter((e) => events === null || !changeText(e))
    .map((e) => ({ key: `episode:${e.id}`, at: e.at, state: eventState(e), text: eventText(e) }));
  const own = events === null ? [] : changes;
  return [...fromMission, ...own, ...fromEpisode].sort(
    (a, b) => Date.parse(b.at) - Date.parse(a.at),
  );
}
