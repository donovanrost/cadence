import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { fetchDashboard, type Runtime } from "../api.ts";

/** Header refresh choices. `off` keeps the snapshot until the range, scope or document changes. */
export const refreshChoices = [
  { value: "off", label: "Off", ms: null },
  { value: "1s", label: "1s", ms: 1_000 },
  { value: "2s", label: "2s", ms: 2_000 },
  { value: "5s", label: "5s", ms: 5_000 },
  { value: "10s", label: "10s", ms: 10_000 },
  { value: "30s", label: "30s", ms: 30_000 },
  { value: "1m", label: "1m", ms: 60_000 },
] as const;
export type RefreshChoice = (typeof refreshChoices)[number]["value"];

const DATA = ["telemetry", "limits", "alarms", "events"] as const;

/**
 * The viewer's snapshot (plan, live step 1): read D5 for the URL's runtime, refetch when the
 * mission channel says the document changed, and, for a sliding range, when its data changed,
 * at most once per refresh interval. No invalidation, no refetch: nothing polls. Reconnects
 * refetch at once (useMissionInvalidation). `paused` (editing, later) stops the data refetches.
 */
export function useDashboardView(
  missionId: Readonly<Ref<string>>,
  dashboardId: Readonly<Ref<string>>,
  runtime: Readonly<Ref<Runtime>>,
  options: Readonly<{
    refreshMs: Readonly<Ref<number | null>>;
    sliding: Readonly<Ref<boolean>>;
    paused: Readonly<Ref<boolean>>;
  }>,
) {
  const key = computed(() =>
    JSON.stringify({ m: missionId.value, id: dashboardId.value, r: runtime.value }),
  );
  const query = useRemoteQuery(key, (_key, signal) =>
    fetchDashboard(missionId.value, dashboardId.value, runtime.value, signal),
  );

  let last = 0;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const dataChanged = () => {
    const ms = options.refreshMs.value;
    if (ms === null || !options.sliding.value || options.paused.value || timer !== null) return;
    const wait = Math.max(0, last + ms - Date.now());
    timer = setTimeout(() => {
      timer = null;
      last = Date.now();
      query.refetch();
    }, wait);
  };
  const mission = computed<string | null>(() => missionId.value);
  useMissionInvalidation(mission, ["dashboards"], query.refetch);
  useMissionInvalidation(mission, DATA, dataChanged, { throttleMs: 250 });
  onScopeDispose(() => {
    if (timer !== null) clearTimeout(timer);
  });
  return query;
}
