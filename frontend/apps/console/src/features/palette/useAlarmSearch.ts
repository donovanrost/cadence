import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, watch, type Ref } from "vue";
import { useRemoteQuery, type ApiResult, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchAlarms, useAlarmPages, type Alarm } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { spacecraftRank } from "./results.ts";

/** Typing settles this long before the alarm search asks the server. */
const DEBOUNCE_MS = 250;
/** Alarms asked of the server per read: the worst first; the sheet says when more match. */
const PAGE = 50;
/** Spacecraft whose name or number matches: at most this many are asked for their alarms. */
const CRAFT = 3;

export type AlarmSearch = Readonly<{
  /** The matching active alarms found, worst first (deduped). */
  alarms: Ref<readonly Alarm[]>;
  /** loading while typing settles or a read is out; failed when either read failed. */
  state: Ref<"loading" | "ready" | "failed">;
  /** More alarms match than were read: the sheet must not look complete (#827). */
  truncated: Ref<boolean>;
  retry: () => void;
}>;

type CraftKey = Readonly<{ m: MissionId; ids: readonly string[] }>;

/** The active alarms of each spacecraft, read together; one failure fails the lot. */
async function fetchCraftAlarms(
  key: CraftKey,
  signal: AbortSignal,
): Promise<ApiResult<{ alarms: readonly Alarm[]; truncated: boolean }>> {
  const reads = await Promise.all(
    key.ids.map((id) =>
      fetchAlarms(key.m, { state: "active", spacecraftId: id, limit: PAGE }, signal),
    ),
  );
  const alarms: Alarm[] = [];
  let truncated = false;
  for (const r of reads) {
    if (!r.ok) return r;
    alarms.push(...r.value.alarms);
    truncated ||= r.value.total > r.value.alarms.length;
  }
  return { ok: true, value: { alarms, truncated } };
}

/**
 * The phone sheet's alarm search (#827): the typed text goes to the server, not into a filter over
 * a first page. Point text is the server's `q` (the point's id, name or limit set); a spacecraft
 * the text names (name or number) is asked for its own alarms. Both settle after the typing does,
 * and the sheet is told when more match than were read.
 */
export function useAlarmSearch(
  missionId: Ref<MissionId>,
  raw: Ref<string>,
  fleet: Ref<readonly FleetSpacecraft[]>,
): AlarmSearch {
  const settled = ref("");
  const waiting = ref(false);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    raw,
    (text) => {
      clearTimeout(timer);
      const next = text.trim().toLowerCase();
      waiting.value = next !== "";
      timer = setTimeout(() => {
        waiting.value = false;
        settled.value = next;
      }, DEBOUNCE_MS);
    },
    { immediate: true },
  );
  onScopeDispose(() => clearTimeout(timer));

  const byPoint = useAlarmPages(missionId, () =>
    settled.value === "" ? null : { state: "active", q: settled.value, limit: PAGE },
  );
  const craftIds = computed(() =>
    settled.value === ""
      ? []
      : fleet.value
          .flatMap((sc) => {
            const rank = spacecraftRank(sc, settled.value);
            return rank === null ? [] : [{ id: sc.id, rank }];
          })
          .sort((a, b) => a.rank - b.rank)
          .slice(0, CRAFT)
          .map((c) => c.id),
  );
  const byCraft = useRemoteQuery(
    computed<CraftKey | null>(() =>
      craftIds.value.length ? { m: missionId.value, ids: craftIds.value } : null,
    ),
    fetchCraftAlarms,
  );
  useMissionInvalidation(missionId, ["alarms"], byCraft.refetch);

  const states = computed<readonly RemoteState<unknown>[]>(() => {
    const reads: RemoteState<unknown>[] = [];
    if (settled.value !== "") reads.push(byPoint.state.value);
    if (craftIds.value.length) reads.push(byCraft.state.value);
    return reads;
  });
  const state = computed<AlarmSearch["state"]["value"]>(() => {
    if (waiting.value || states.value.some((s) => s.status === "loading")) return "loading";
    return states.value.some((s) => s.status === "failed") ? "failed" : "ready";
  });
  const alarms = computed<readonly Alarm[]>(() => {
    const merged: Alarm[] = [];
    const p = byPoint.state.value;
    if (settled.value !== "" && p.status === "ready") merged.push(...p.value.alarms);
    const c = byCraft.state.value;
    if (craftIds.value.length && c.status === "ready") merged.push(...c.value.alarms);
    return [...new Map(merged.map((a) => [a.id, a])).values()];
  });
  const truncated = computed(() => {
    const p = byPoint.state.value;
    const c = byCraft.state.value;
    return (
      (settled.value !== "" && p.status === "ready" && p.value.next !== null) ||
      (craftIds.value.length > 0 && c.status === "ready" && c.value.truncated)
    );
  });
  const retry = () => {
    byPoint.refetch();
    byCraft.refetch();
  };
  return { alarms, state, truncated, retry };
}
