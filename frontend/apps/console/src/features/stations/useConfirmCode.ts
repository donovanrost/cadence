import { ref, shallowRef } from "vue";
import { failureOutcome, refreshConfigState, stageChange } from "@/features/changes/index.ts";
import type { Station } from "./api.ts";

/**
 * U25: confirming a suggested code stages a normal ground_station change writing `code`. The
 * suggestion is never stored by itself; until the change set is applied the read still says null.
 */
export function useConfirmCode(missionId: () => string) {
  const staged = shallowRef<ReadonlySet<string>>(new Set());
  const busy = ref<string | null>(null);
  const failure = ref<string | null>(null);

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
        failure.value = `${station.display_name}: ${failureOutcome(result.error, "staged").sentence}`;
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
