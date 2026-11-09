import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope, useSession } from "@/shell/index.ts";
import { fetchPeople } from "@/features/alarms/index.ts";
import type { PersonName } from "./words.ts";

/**
 * Actor documents carry only a user id (DECISIONS #30), so names come from the organization's
 * people read. The viewer is "You"; a service actor (no user) is "Cadence".
 */
export function usePeopleNames(): PersonName {
  const scope = useMissionScope();
  const session = useSession();
  const people = useRemoteQuery(
    () => scope.value.organization.id,
    (org, signal) => fetchPeople(org, signal),
  );
  return (userId) => {
    if (userId === null) return "Cadence";
    if (userId === session.user.id) return "You";
    const s = people.state.value;
    const m = s.status === "ready" ? s.value.members.find((p) => p.user_id === userId) : undefined;
    return m?.display_name ?? "A teammate";
  };
}
