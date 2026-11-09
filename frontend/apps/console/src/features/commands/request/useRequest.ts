import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope, useSession } from "@/shell/index.ts";
import { fetchPeople } from "@/features/alarms/index.ts";
import { fetchGroups } from "../groups/api.ts";
import { fetchGroup, fetchReview } from "../groups/show.ts";

/**
 * One command request (group) for Approve and Uplink & verify: the group, the preflight re-run at
 * review (only while it awaits a GO), the pending queue, and people's names. Refetches on
 * `commanding` until the `command_group:<id>` push lands (commanding.md §Not yet).
 */
export function useRequest(groupId: Ref<string>) {
  const scope = useMissionScope();
  const session = useSession();
  const missionId = computed(() => scope.value.mission.id);

  const group = useRemoteQuery(groupId, (id, signal) => fetchGroup(missionId.value, id, signal));
  const pending = computed(
    () =>
      group.state.value.status === "ready" && group.state.value.value.state === "approval_pending",
  );
  const review = useRemoteQuery(
    () => (pending.value ? groupId.value : null),
    (id, signal) => fetchReview(missionId.value, id, signal),
  );
  const queue = useRemoteQuery(missionId, (m, signal) =>
    fetchGroups(m, { states: ["approval_pending"] }, signal),
  );
  const people = useRemoteQuery(
    () => scope.value.organization.id,
    (org, signal) => fetchPeople(org, signal),
  );
  const missionRef = computed<string | null>(() => missionId.value);
  const refetch = () => {
    group.refetch();
    if (pending.value) review.refetch();
    queue.refetch();
  };
  useMissionInvalidation(missionRef, ["commanding"], refetch);
  useMissionInvalidation(missionRef, ["contacts", "catalog"], () => {
    if (pending.value) review.refetch();
  });

  const nameOf = (userId: string | null) => {
    if (userId === null) return "Cadence";
    if (userId === session.user.id) return "You";
    const s = people.state.value;
    const m = s.status === "ready" ? s.value.members.find((p) => p.user_id === userId) : undefined;
    return m?.display_name ?? "A teammate";
  };

  return { missionId, group, review, queue, nameOf, refetch, viewerId: session.user.id };
}
