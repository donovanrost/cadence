import { computed, type Ref } from "vue";
import { array, object, token } from "@/api/decode.ts";
import { useChannelEvent } from "./useChannelEvent.ts";

export const missionResources = [
  "alarms",
  "catalog",
  "commanding",
  "configuration",
  "dashboards",
  "data_sources",
  "events",
  "limits",
  "settings",
  "spacecraft",
  "telemetry",
] as const;
export type MissionResource = (typeof missionResources)[number];

// Unknown resource names are tolerated so the server can add areas without breaking clients.
const invalidate = object({ resources: array(token, 64) });

/**
 * Calls `refetch` when the server invalidates any of `resources` for the mission, and after a
 * socket reconnect. Pass the mission id (not slug); null pauses.
 */
export function useMissionInvalidation(
  missionId: Readonly<Ref<string | null>>,
  resources: readonly MissionResource[],
  refetch: () => void,
) {
  const wanted = new Set<string>(resources);
  const topic = computed(() => (missionId.value ? `mission:${missionId.value}` : null));
  useChannelEvent(topic, "invalidate", invalidate, {
    onEvent: (payload) => {
      if (payload.resources.some((resource) => wanted.has(resource))) refetch();
    },
    onResync: refetch,
  });
}
