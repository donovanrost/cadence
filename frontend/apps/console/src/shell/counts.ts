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
      limits_configured: d.boolean,
    }),
  ),
  commands: d.nullable(d.object({ open: d.integer, awaiting_viewer: d.integer })),
  fleet: d.nullable(d.object({ total: d.integer })),
  contacts: d.nullable(d.object({ in_contact: d.integer })),
  // U31 (3d891b4b): open "needs acknowledgment" items, for the mobile Now badge. Optional so an
  // older server's /counts still decodes.
  attention: d.optional(d.nullable(d.object({ open: d.integer, acknowledged: d.integer }))),
  /**
   * U38: whether the mission runtime applied the active configuration (domain
   * MissionRuntimeStatus, same source and 60 s debounce as the mission_runtime attention item).
   * Optional until api-ops ships it; null = nothing to say.
   */
  runtime: d.optional(
    d.nullable(
      d.object({
        state: d.token,
        reason: d.optional(d.nullable(d.token)),
        desired_generation: d.optional(d.nullable(d.integer)),
        applied_generation: d.optional(d.nullable(d.integer)),
        /** When the reconciler first failed for the desired generation. */
        since: d.optional(d.nullable(d.timestamp)),
        /** When it last applied a generation (the "resumed at" time). */
        applied_at: d.optional(d.nullable(d.timestamp)),
        /** When the desired generation was activated (asked of domain). */
        activated_at: d.optional(d.nullable(d.timestamp)),
      }),
    ),
  ),
});
export type RuntimeStatus = NonNullable<OpsCounts["runtime"]>;
export type OpsCounts = Decoded<typeof countsReader>;

function fetchCounts(missionId: string, signal: AbortSignal): Promise<ApiResult<OpsCounts>> {
  return request(`/missions/${encodeURIComponent(missionId)}/counts`, countsReader, { signal });
}

const GAP_MS = 5_000;

/**
 * Shell counts (Ops rail, on-call tabs, runtime status). Refetches on alarms/attention/commanding/
 * spacecraft/configuration invalidations,
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
  // `configuration`: an applied change set moves the runtime generation (CONVERGING, fe-setup).
  useMissionInvalidation(
    missionId,
    ["alarms", "attention", "commanding", "spacecraft", "configuration"],
    refetch,
  );
  onScopeDispose(() => {
    if (timer !== null) clearTimeout(timer);
  });
  const counts = computed(() =>
    query.state.value.status === "ready" ? query.state.value.value : null,
  );
  return { counts };
}
