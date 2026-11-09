import { computed, onScopeDispose, ref, watch, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchPoints } from "@/features/telemetry/index.ts";
import { parseQuery, PER_GROUP, type PaletteItem } from "./results.ts";
import { pointItems, telemetryQuery, type TelemetryQuery } from "./telemetry.ts";

/** Typing settles this long before the point search asks the server (Palette.md: 120 ms). */
const DEBOUNCE_MS = 120;

/**
 * ⌘K Telemetry rows from the M23 point search. Prefixed queries (`#` spacecraft, `>` commands,
 * `@` stations) skip it. Up to four groups' worth come back, so "Show all" has rows to show.
 */
export function usePointSearch(
  missionId: Ref<string | null>,
  raw: Ref<string>,
  fleet: Ref<readonly FleetSpacecraft[]>,
): Ref<PaletteItem[]> {
  const settled = ref<{ m: string; tq: TelemetryQuery } | null>(null);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    [raw, missionId, fleet],
    () => {
      clearTimeout(timer);
      const { only } = parseQuery(raw.value);
      const tq = only === null ? telemetryQuery(raw.value, fleet.value) : null;
      const m = missionId.value;
      timer = setTimeout(() => (settled.value = m && tq ? { m, tq } : null), DEBOUNCE_MS);
    },
    { immediate: true },
  );
  onScopeDispose(() => clearTimeout(timer));

  const query = useRemoteQuery(settled, ({ m, tq }, signal) =>
    fetchPoints(
      m,
      { q: tq.q, ...(tq.spacecraft ? { spacecraftId: tq.spacecraft.id } : {}) },
      signal,
    ),
  );
  return computed(() => {
    const s = query.state.value;
    const tq = settled.value?.tq;
    if (s.status !== "ready" || !tq) return [];
    return pointItems(s.value.points.slice(0, PER_GROUP * 4), tq.spacecraft);
  });
}
