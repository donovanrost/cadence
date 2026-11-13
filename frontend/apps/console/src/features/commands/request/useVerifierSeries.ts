import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import { fetchVerifierSeries } from "../groups/series.ts";

/**
 * M26 verifier series, read once for Uplink: U2 plots it, N Needs you reads each target's last
 * value from it. Refetches on commanding, and on telemetry at most every 10 s.
 */
export function useVerifierSeries(missionId: Ref<MissionId>, groupId: Ref<string>) {
  const series = useRemoteQuery(
    computed(() => ({ m: missionId.value, g: groupId.value })),
    (k, signal) => fetchVerifierSeries(k.m, k.g, signal),
  );
  useMissionInvalidation(missionId, ["commanding"], series.refetch);
  const slow = throttle(series.refetch, 10_000);
  useMissionInvalidation(missionId, ["telemetry"], slow.call);
  const ready = computed(() =>
    series.state.value.status === "ready" ? series.state.value.value : null,
  );
  return { state: series.state, refetch: series.refetch, ready };
}
export type VerifierSeriesQuery = ReturnType<typeof useVerifierSeries>;
