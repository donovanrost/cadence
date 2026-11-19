import type { MissionId } from "@/api/index.ts";
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
  missionId: Ref<MissionId | null>,
  raw: Ref<string>,
  fleet: Ref<readonly FleetSpacecraft[]>,
): { items: Ref<PaletteItem[]>; pending: Ref<boolean> } {
  const settled = ref<{ m: MissionId; tq: TelemetryQuery } | null>(null);
  /** True from a keystroke that will ask the server until the debounce settles. */
  const waiting = ref(false);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    [raw, missionId, fleet],
    () => {
      clearTimeout(timer);
      const { only } = parseQuery(raw.value);
      const tq = only === null ? telemetryQuery(raw.value, fleet.value) : null;
      const m = missionId.value;
      waiting.value = Boolean(m && tq);
      timer = setTimeout(() => {
        waiting.value = false;
        settled.value = m && tq ? { m, tq } : null;
      }, DEBOUNCE_MS);
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
  // While the next search is out, the last results stay (Palette.md: no flicker).
  let last: PaletteItem[] = [];
  const items = computed(() => {
    const s = query.state.value;
    const tq = settled.value?.tq;
    if (!tq) return (last = []);
    if (s.status === "loading") return last;
    if (s.status !== "ready") return (last = []);
    return (last = pointItems(s.value.points.slice(0, PER_GROUP * 4), tq.spacecraft));
  });
  const pending = computed(
    () => waiting.value || (settled.value !== null && query.state.value.status === "loading"),
  );
  return { items, pending };
}
