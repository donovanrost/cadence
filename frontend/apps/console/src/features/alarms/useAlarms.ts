import type { Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchAlarms } from "./api.ts";

/** Active alarms for the mission; refetched on limit-state transitions and definition changes. */
export function useActiveAlarms(missionId: Ref<string>) {
  const query = useRemoteQuery(missionId, (id, signal) =>
    fetchAlarms(id, { state: "active" }, signal),
  );
  useMissionInvalidation(missionId, ["alarms", "limits"], query.refetch);
  return query;
}
