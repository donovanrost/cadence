import type { MissionId } from "@/api/index.ts";
import { ref, shallowRef } from "vue";
import {
  failureOutcome,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import type { Station } from "./api.ts";

/**
 * U25: confirming a suggested code stages a normal ground_station change writing `code`. The
 * suggestion is never stored by itself; until the change set is applied the read still says null.
 */
export function useConfirmCode(missionId: () => MissionId) {
  const staged = shallowRef<ReadonlySet<string>>(new Set());
  const busy = ref<string | null>(null);
  /** Named for its station, with its link (e.g. U79 'Open change set'). */
  const failure = ref<FailureOutcome | null>(null);

  async function confirm(station: Station) {
    const code = station.suggested_code;
    if (!code || busy.value) return;
    busy.value = station.id;
    failure.value = null;
    try {
      const result = await stageChange(missionId(), {
        summary: `${station.display_name} · code → ${code}`,
        source: { surface: "stations" },
        ops: [
          {
            kind: "ground_station",
            action: "update",
            entity_id: station.id,
            changes: [{ path: "code", value: code }],
          },
        ],
      });
      if (!result.ok) {
        const outcome = failureOutcome(result.error, "staged");
        failure.value = { ...outcome, sentence: `${station.display_name}: ${outcome.sentence}` };
        return;
      }
      staged.value = new Set([...staged.value, station.id]);
      refreshConfigState(missionId());
    } finally {
      busy.value = null;
    }
  }
  return { staged, busy, failure, confirm };
}
