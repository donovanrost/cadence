import type { ApiResult, MissionId } from "@/api/index.ts";
import { request } from "@/api/index.ts";
import type { Decoded } from "@/api/index.ts";
import { passesWithContactsReader } from "../handStarted.ts";
import {
  DAY_MS,
  HAND_STARTED_LISTED,
  isoDay,
  weekDays,
  type HistoryRow,
  type WeekSpan,
} from "./history.ts";

/**
 * History's own read of `GET /passes` (contacts.md) over a fixed range: no sliding window, and the
 * filters History offers. `spacecraft_id` and `states` filter in SQL before the 500 cut; `station`
 * filters after it (api, 11-16). History also filters states on its side, to split Confirmed from
 * In contact.
 */
export type HistoryFilter = Readonly<{
  spacecraftId: string | null;
  station: string | null;
  states: readonly string[] | null;
}>;

export function fetchHistoryPasses(
  missionId: MissionId,
  range: Readonly<{ from: number; to: number }>,
  filter: HistoryFilter,
  signal?: AbortSignal,
) {
  const params = new URLSearchParams({
    from: new Date(range.from).toISOString(),
    to: new Date(range.to).toISOString(),
  });
  if (filter.spacecraftId) params.set("spacecraft_id", filter.spacecraftId);
  if (filter.station) params.set("station", filter.station);
  if (filter.states?.length) params.set("states", filter.states.join(","));
  // Newest first in SQL, so a cut read keeps the newest 500 (U78); the default is ascending.
  params.set("order", "desc");
  if (HAND_STARTED_LISTED) params.set("include", "hand_started");
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes?${params.toString()}`,
    passesWithContactsReader,
    signal ? { signal } : {},
  );
}

/**
 * A UTC day the read still cut at 500. The read is newest first, so its passes that started
 * before `back` (the earliest start shown that day) are the missing ones.
 */
export type ShortDay = Readonly<{ day: string; back: number }>;

/** The read's shape (passes and hand-started contacts) plus the days still cut. */
export type WeekLedger = Decoded<typeof passesWithContactsReader> &
  Readonly<{ shortDays: readonly ShortDay[] }>;

/** The earliest start among the passes that started on `day` (the newest 500 of it, descending). */
function earliestStart(passes: readonly HistoryRow[], day: { from: number; to: number }): number {
  let back = day.to;
  for (const p of passes) {
    const t = Date.parse(p.starts_at);
    if (t >= day.from && t < day.to && t < back) back = t;
  }
  return back;
}

/**
 * A week of passes. When the read is truncated it re-reads the week one UTC day at a time (U78,
 * api OK'd the load: user-initiated, truncated weeks only) and names the days still cut.
 */
export async function fetchWeekLedger(
  missionId: MissionId,
  span: WeekSpan,
  filter: HistoryFilter,
  signal?: AbortSignal,
): Promise<ApiResult<WeekLedger>> {
  const week = { from: span.from, to: span.from + 7 * DAY_MS };
  const whole = await fetchHistoryPasses(missionId, week, filter, signal);
  if (!whole.ok || !whole.value.truncated) {
    return whole.ok ? { ok: true, value: { ...whole.value, shortDays: [] } } : whole;
  }
  const days = weekDays(span);
  const reads = await Promise.all(
    days.map((day) => fetchHistoryPasses(missionId, day, filter, signal)),
  );
  const passes: HistoryRow[] = [];
  const shortDays: ShortDay[] = [];
  for (const [i, read] of reads.entries()) {
    const day = days[i];
    if (!read.ok) return read;
    if (!day) continue;
    passes.push(...read.value.passes);
    if (read.value.truncated) {
      shortDays.push({ day: isoDay(day.from), back: earliestStart(read.value.passes, day) });
    }
  }
  return {
    ok: true,
    value: { ...whole.value, truncated: shortDays.length > 0, passes, shortDays },
  };
}
