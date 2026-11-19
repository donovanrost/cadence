import { computed, type ComputedRef, type Ref } from "vue";
import { useRemoteQuery, type MissionId } from "@/api/index.ts";
import { fetchEndpoints, type TargetEndpoints } from "../groups/api.ts";

/**
 * C4: each target's uplink endpoints and what routing resolves (DECISIONS #41), by spacecraft id.
 * The query key is typed (A4 compares keys structurally) and carries the mission, so a mission
 * change refetches even when the target ids are the same.
 */
export function useTargetEndpoints(
  missionId: Readonly<Ref<MissionId>>,
  spacecraftIds: () => readonly string[],
): ComputedRef<ReadonlyMap<string, TargetEndpoints>> {
  const read = useRemoteQuery(
    () => {
      const ids = spacecraftIds();
      return ids.length ? { missionId: missionId.value, ids } : null;
    },
    (key, signal) => fetchEndpoints(key.missionId, key.ids, signal),
  );
  return computed(
    () =>
      new Map(
        read.state.value.status === "ready"
          ? read.state.value.value.map((e) => [e.spacecraft_id, e] as const)
          : [],
      ),
  );
}
