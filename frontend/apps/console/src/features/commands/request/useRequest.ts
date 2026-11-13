import type { MissionId } from "@/api/index.ts";
import { computed, shallowRef, watch, type Ref } from "vue";
import { decoders as d, useRemoteQuery, type RemoteState } from "@/api/index.ts";
import { useChannelEvent, useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope, useSession } from "@/shell/index.ts";
import { fetchGroups } from "../groups/api.ts";
import { usePeopleNames } from "../groups/usePeopleNames.ts";
import { fetchGroup, fetchReview, groupReader, type Group } from "../groups/show.ts";

const groupPush = d.object({ seq: d.integer, group: groupReader });

/**
 * One command request (group) for Approve and Uplink & verify: the group (live over
 * `command_group:<mission>:<id>`, realtime.md — each push replaces the copy wholesale), the
 * preflight re-run at review (only while it awaits a GO), the pending queue, and people's names.
 */
export function useRequest(groupId: Ref<string>) {
  const scope = useMissionScope();
  const session = useSession();
  const missionId = computed(() => scope.value.mission.id);

  const fetched = useRemoteQuery(groupId, (id, signal) => fetchGroup(missionId.value, id, signal));
  /** The newest pushed view; cleared when the request on screen changes. */
  const pushed = shallowRef<{ group: Group; at: Date } | null>(null);
  watch(groupId, () => (pushed.value = null));
  useChannelEvent(
    computed(() => `command_group:${missionId.value}:${groupId.value}`),
    "group",
    groupPush,
    {
      // seq restarts at 1 on every (re)join and pushes arrive in order, so the latest one wins.
      onEvent: (p) => {
        if (p.group.id === groupId.value) pushed.value = { group: p.group, at: new Date() };
      },
      onResync: () => fetched.refetch(),
    },
  );
  /** The newer of the pushed view and the fetch (the fetch also carries loading / failed). */
  const state = computed<RemoteState<Group>>(() => {
    const f = fetched.state.value;
    const p = pushed.value;
    if (!p || (f.status === "ready" && f.receivedAt > p.at)) return f;
    return { status: "ready", value: p.group, receivedAt: p.at };
  });

  const pending = computed(
    () => state.value.status === "ready" && state.value.value.state === "approval_pending",
  );
  const review = useRemoteQuery(
    () => (pending.value ? groupId.value : null),
    (id, signal) => fetchReview(missionId.value, id, signal),
  );
  const queue = useRemoteQuery(missionId, (m, signal) =>
    fetchGroups(m, { states: ["approval_pending"] }, signal),
  );
  const nameOf = usePeopleNames();
  const missionRef = computed<MissionId | null>(() => missionId.value);
  const refetch = () => {
    fetched.refetch();
    if (pending.value) review.refetch();
    queue.refetch();
  };
  // The group itself is pushed; the pending queue and the review re-check aren't.
  useMissionInvalidation(missionRef, ["commanding"], () => {
    if (pending.value) review.refetch();
    queue.refetch();
  });
  useMissionInvalidation(missionRef, ["contacts", "catalog"], () => {
    if (pending.value) review.refetch();
  });

  return {
    missionId,
    group: { state, refetch: fetched.refetch },
    review,
    queue,
    nameOf,
    refetch,
    viewerId: session.user.id,
  };
}
