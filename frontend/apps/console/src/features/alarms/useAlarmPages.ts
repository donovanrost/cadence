import type { MissionId } from "@/api/index.ts";
import { computed, toValue, type MaybeRefOrGetter, type Ref } from "vue";
import { usePagedQuery, type PageFetcher, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchAlarmPage, type Alarm, type AlarmQuery, type Alarms } from "./api.ts";

/** A page's envelope besides its alarms: the mission summary and the matching total. */
export type AlarmsMeta = Omit<Alarms, "alarms">;
type Key = Readonly<{ missionId: MissionId; query: AlarmQuery }>;

/**
 * The alarms loaded so far, in the `Alarms` shape plus `next`: the cursor of the page not yet
 * loaded (null when every matching alarm is). `total` is how many match, so a screen that shows
 * `alarms.length` of `total` never looks complete when it isn't (#827).
 */
export type AlarmsPage = Alarms & Readonly<{ next: string | null }>;

const fetchPage: PageFetcher<Key, Alarm, AlarmsMeta> = async (key, cursor, signal) => {
  const r = await fetchAlarmPage(key.missionId, key.query, cursor, signal);
  if (!r.ok) return r;
  const { alarms, ...meta } = r.value.value;
  return { ok: true, value: { items: alarms, next: r.value.nextCursor, meta } };
};

/**
 * A paged alarm read (usePagedQuery, #176): the first page when the query is set (null pauses),
 * `more()` for the next, and a reload from the first page up to the rows shown on a live `alarms`
 * or `limits` change. `state` has the `Alarms` shape with `next`, so a screen that read the whole
 * list reads it unchanged and says when it holds only a part.
 */
export function useAlarmPages(
  missionId: Ref<MissionId>,
  query: MaybeRefOrGetter<AlarmQuery | null>,
) {
  const key = computed<Key | null>(() => {
    const q = toValue(query);
    return q === null ? null : { missionId: missionId.value, query: q };
  });
  const paged = usePagedQuery(key, fetchPage, (alarm) => alarm.id);
  useMissionInvalidation(missionId, ["alarms", "limits"], paged.refetch);
  const state = computed<RemoteState<AlarmsPage>>(() => {
    const s = paged.state.value;
    return s.status === "ready"
      ? { ...s, value: { ...s.value.meta, alarms: [...s.value.items], next: s.value.next } }
      : s;
  });
  return {
    state,
    more: paged.more,
    moreBusy: paged.moreBusy,
    moreError: paged.moreError,
    refreshError: paged.refreshError,
    refetch: paged.refetch,
  };
}

export type AlarmPages = ReturnType<typeof useAlarmPages>;
