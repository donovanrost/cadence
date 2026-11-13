import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, watch, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchCatalog } from "@/features/commands/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import { parseQuery, PER_GROUP, type PaletteItem } from "./results.ts";
import { catalogQuery, commandItems, stationItems } from "./sources.ts";

/** Typing settles this long before the catalog search asks the server (Palette.md: 120 ms). */
const DEBOUNCE_MS = 120;

/**
 * ⌘K Commands and Stations groups. The catalog is searched on the server (debounced, only for
 * viewers who can request commands: the rows open a new request); stations are read once per
 * open palette and matched locally.
 */
export function useSourceSearch(
  missionId: Ref<MissionId | null>,
  raw: Ref<string>,
  canCommand: Ref<boolean>,
) {
  const settled = ref<{ m: MissionId; q: string } | null>(null);
  const waiting = ref(false);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    [raw, missionId, canCommand],
    () => {
      clearTimeout(timer);
      const { text, only } = parseQuery(raw.value);
      const q = canCommand.value ? catalogQuery(text, only) : null;
      const m = missionId.value;
      waiting.value = m !== null && q !== null;
      timer = setTimeout(() => {
        waiting.value = false;
        settled.value = m !== null && q !== null ? { m, q } : null;
      }, DEBOUNCE_MS);
    },
    { immediate: true },
  );
  onScopeDispose(() => clearTimeout(timer));

  const catalog = useRemoteQuery(settled, ({ m, q }, signal) => fetchCatalog(m, q, signal));
  const stations = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
  useMissionInvalidation(missionId, ["configuration", "stations"], stations.refetch);

  let lastCommands: PaletteItem[] = [];
  const items = computed<PaletteItem[]>(() => {
    const { text, only } = parseQuery(raw.value);
    const out: PaletteItem[] = [];
    const c = catalog.state.value;
    const q = settled.value?.q;
    // While the next catalog search is out, the last commands stay (Palette.md: no flicker).
    if (q === undefined) lastCommands = [];
    else if (c.status === "ready")
      lastCommands = commandItems(c.value.commands.slice(0, PER_GROUP * 4), q.toLowerCase());
    else if (c.status !== "loading") lastCommands = [];
    if (only === null || only === "commands") out.push(...lastCommands);
    const s = stations.state.value;
    // An empty unprefixed query shows Pages, not every station.
    if (s.status === "ready" && (only === "stations" || (only === null && text !== "")))
      out.push(...stationItems(s.value, text));
    return out;
  });
  const stationCount = computed(() => {
    const s = stations.state.value;
    return s.status === "ready"
      ? s.value.filter((st) => st.lifecycle_state === "active").length
      : null;
  });
  const pending = computed(
    () => waiting.value || (settled.value !== null && catalog.state.value.status === "loading"),
  );
  return { items, stationCount, pending };
}
