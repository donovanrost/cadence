import { computed, watch, type Ref } from "vue";
import { usePagedQuery, useRemoteQuery, type MissionId } from "@/api/index.ts";
import {
  fetchAllEvents,
  fetchEventsPage,
  fetchTargetsPage,
  type EventsKey,
  type TargetsKey,
} from "../groups/pages.ts";
import type { EventKind, Group } from "../groups/show.ts";
import type { MemberStage } from "../groups/api.ts";

export type TargetFilter = Readonly<{
  stages?: readonly MemberStage[];
  q?: string;
  needsYou?: boolean;
  unnamed?: boolean;
}>;

/**
 * #795: a group's targets a page at a time, for the list on screen. The pages shown are read again
 * whenever the group's `targets_page.revision` moves (any target's stage changed), so a list never
 * shows a stage older than the summary above it.
 */
export function useGroupTargets(
  missionId: Ref<MissionId>,
  group: Ref<Group>,
  filter: Ref<TargetFilter> = computed(() => ({})),
) {
  const key = computed<TargetsKey>(() => ({
    missionId: missionId.value,
    groupId: group.value.id,
    ...filter.value,
  }));
  const pages = usePagedQuery(key, fetchTargetsPage, (t) => t.spacecraft_id, {
    // A filter change keeps the rows shown until its first page answers (the search box stays).
    scopeOf: (k) => ({ missionId: k.missionId, groupId: k.groupId }),
  });
  watch(
    () => group.value.targets_page.revision,
    (now, was) => {
      if (was !== undefined && now !== was) pages.refetch();
    },
  );
  return pages;
}

/**
 * #795: a group's events a page at a time, the latest first; Load older reads back. The pages
 * shown are read again when `events_page.total` moves (new events were written).
 */
export function useGroupEvents(
  missionId: Ref<MissionId>,
  group: Ref<Group>,
  kinds: readonly EventKind[] = [],
) {
  const key = computed<EventsKey>(() => ({
    missionId: missionId.value,
    groupId: group.value.id,
    kinds,
  }));
  const pages = usePagedQuery(key, fetchEventsPage, (e) => e.id);
  watch(
    () => group.value.events_page.total,
    (now, was) => {
      if (was !== undefined && now !== was) pages.refetch();
    },
  );
  return pages;
}

/**
 * #795: the request's HOLD acknowledgements (`hold_acknowledged`, written at submit, so the oldest
 * events), read on their own so a long log never hides them from the GO check. Read again when
 * the group says events were added.
 */
export function useHoldEvents(missionId: Ref<MissionId>, group: Ref<Group>) {
  return useRemoteQuery(
    computed(() => ({
      missionId: missionId.value,
      groupId: group.value.id,
      total: group.value.events_page.total,
    })),
    (k, signal) => fetchAllEvents({ ...k, kinds: ["hold_acknowledged"] }, signal),
  );
}
