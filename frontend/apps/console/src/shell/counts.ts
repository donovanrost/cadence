import { computed, onScopeDispose, type Ref } from "vue";
import { decoders as d, request, useRemoteQuery, type ApiResult, type Decoded } from "@/api";
import { useMissionInvalidation } from "@/live";

/** Contract: docs/apogee/api/ops.md, `GET /missions/:id/counts`. A null count means "can't compute". */
export const countsReader = d.object({
  observed_at: d.timestamp,
  alarms: d.nullable(
    d.object({
      active: d.integer,
      critical: d.integer,
      caution: d.integer,
      unacknowledged: d.integer,
    }),
  ),
  commands: d.nullable(d.object({ open: d.integer, awaiting_viewer: d.integer })),
  fleet: d.nullable(d.object({ total: d.integer })),
  contacts: d.nullable(d.object({ in_contact: d.integer })),
});
export type OpsCounts = Decoded<typeof countsReader>;

function fetchCounts(missionId: string, signal: AbortSignal): Promise<ApiResult<OpsCounts>> {
  return request(`/missions/${encodeURIComponent(missionId)}/counts`, countsReader, { signal });
}

const GAP_MS = 5_000;

/**
 * Shell counts (Ops rail, on-call tabs). Refetches on alarms/commanding/spacecraft invalidations,
 * at most every 5 s with one trailing refetch. `counts` is null until the first read lands.
 */
export function useOpsCounts(missionId: Readonly<Ref<string | null>>) {
  const query = useRemoteQuery(missionId, fetchCounts);
  let last = 0;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const refetch = () => {
    if (timer !== null) return;
    const wait = Math.max(0, last + GAP_MS - Date.now());
    timer = setTimeout(() => {
      timer = null;
      last = Date.now();
      query.refetch();
    }, wait);
  };
  useMissionInvalidation(missionId, ["alarms", "commanding", "spacecraft"], refetch);
  onScopeDispose(() => {
    if (timer !== null) clearTimeout(timer);
  });
  const counts = computed(() =>
    query.state.value.status === "ready" ? query.state.value.value : null,
  );
  return { counts };
}
