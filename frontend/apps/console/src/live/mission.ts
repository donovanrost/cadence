import { computed, type Ref } from "vue";
import { array, object, token } from "@/api/decode.ts";
import type { MissionId } from "@/api/ids.ts";
import { coalesce } from "./coalesce.ts";
import { useChannelEvent } from "./useChannelEvent.ts";

export const missionResources = [
  // L10 (plans/activations.md): app activation requests created or decided.
  "activations",
  "alarms",
  "attention",
  "catalog",
  "commanding",
  "configuration",
  "contact_plans",
  "contacts",
  "dashboards",
  "data_sources",
  "events",
  "limits",
  "pass_results",
  "settings",
  "spacecraft",
  "stations",
  "telemetry",
] as const;
export type MissionResource = (typeof missionResources)[number];

// Unknown resource names are tolerated so the server can add areas without breaking clients.
const invalidate = object({ resources: array(token, 64) });

/**
 * Calls `refetch` when the server invalidates any of `resources` for the mission, and after a
 * socket reconnect. Takes the MissionId (the slug can't be passed, §12C); null pauses. Bursts are coalesced: the first
 * invalidation refetches at once, the rest of a `throttleMs` window (default 1 s) refetch once
 * at its end. A reconnect refetches immediately.
 */
export function useMissionInvalidation(
  missionId: Readonly<Ref<MissionId | null>>,
  resources: readonly MissionResource[],
  refetch: () => void,
  options: Readonly<{ throttleMs?: number }> = {},
) {
  const wanted = new Set<string>(resources);
  const topic = computed(() => (missionId.value ? `mission:${missionId.value}` : null));
  const run = coalesce(refetch, options.throttleMs ?? 1000);
  useChannelEvent(topic, "invalidate", invalidate, {
    onEvent: (payload) => {
      if (payload.resources.some((resource) => wanted.has(resource))) run.call();
    },
    onResync: run.flush,
  });
}
