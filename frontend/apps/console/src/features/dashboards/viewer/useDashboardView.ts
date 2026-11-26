import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery, type ApiResult } from "@/api";
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

export type LiveOptions = Readonly<{
  refreshMs: Readonly<Ref<number | null>>;
  sliding: Readonly<Ref<boolean>>;
  paused: Readonly<Ref<boolean>>;
}>;

/**
 * A live dashboard read (plan, live step 1), shared by the viewer, share links and present mode:
 * read for the key, refetch when the mission channel says dashboards changed, and, for a sliding
 * range, when its data changed, at most once per refresh interval. No invalidation, no refetch:
 * nothing polls. Reconnects refetch at once (useMissionInvalidation). `paused` (editing) stops
 * the data refetches.
 */
export function useLiveRead<T>(
  missionId: Readonly<Ref<MissionId>>,
  key: Readonly<Ref<string | null>>,
  fetch: (signal: AbortSignal) => Promise<ApiResult<T>>,
  options: LiveOptions,
) {
  const query = useRemoteQuery(key, (_key, signal) => fetch(signal));
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
  const mission = computed<MissionId | null>(() => missionId.value);
  useMissionInvalidation(mission, ["dashboards"], query.refetch);
  useMissionInvalidation(mission, DATA, dataChanged, { throttleMs: 250 });
  onScopeDispose(() => {
    if (timer !== null) clearTimeout(timer);
  });
  return query;
}

/** The viewer's D5 read for the URL's runtime. */
export function useDashboardView(
  missionId: Readonly<Ref<MissionId>>,
  /** null pauses the read (Present between dashboards). */
  dashboardId: Readonly<Ref<DashboardId | null>>,
  runtime: Readonly<Ref<Runtime>>,
  options: LiveOptions,
) {
  const key = computed(() =>
    dashboardId.value
      ? JSON.stringify({ m: missionId.value, id: dashboardId.value, r: runtime.value })
      : null,
  );
  return useLiveRead(
    missionId,
    key,
    (signal) => {
      const id = dashboardId.value;
      // The key is null without an id, so the read never runs then; say so if it ever did.
      if (id === null)
        return Promise.resolve({
          ok: false as const,
          error: { kind: "not_found" as const, code: "not_found", message: "No dashboard" },
        });
      return fetchDashboard(missionId.value, id, runtime.value, signal);
    },
    options,
  );
}
