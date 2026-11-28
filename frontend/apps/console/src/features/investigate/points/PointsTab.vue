<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import { usePagedQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatCount,
  formatCountdown,
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApTable,
  ApTag,
  type ApColumn,
} from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import {
  conditionText,
  detailWords,
  fetchPointConditionPage,
  freshnessWord,
  markState,
  sourceWords,
  valueText,
  type PointCondition,
  type PointsMeta,
  type PointsQuery,
} from "./api.ts";

/**
 * Tab · Points (#143): every point of this spacecraft with its current condition, from both
 * stores, critical and caution first, a stale point named stale. One row per (point, source): a
 * ground limit says when its job ran, a monitoring rule is live.
 */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const filter = ref<PointsQuery["state"]>("all");

const key = computed(() => ({
  missionId: missionId.value,
  spacecraftId: props.sc.id,
  query: { state: filter.value } satisfies PointsQuery,
}));
const paged = usePagedQuery(
  key,
  async (k, cursor, signal) => {
    const r = await fetchPointConditionPage(k.missionId, k.spacecraftId, k.query, cursor, signal);
    if (!r.ok) return r;
    return {
      ok: true,
      value: { items: r.value.value, next: r.value.nextCursor, meta: r.value.meta },
    };
  },
  rowKey,
);
useMissionInvalidation(missionId, ["alarms", "limits"], paged.refetch);

const state = paged.state;
const meta = computed<PointsMeta | null>(() =>
  state.value.status === "ready" ? state.value.value.meta : null,
);
const rows = computed<readonly PointCondition[]>(() =>
  state.value.status === "ready" ? state.value.value.items : [],
);
const hasMore = computed(() => state.value.status === "ready" && state.value.value.next !== null);

function rowKey(row: PointCondition): string {
  return `${row.point_id}|${row.source}|${row.policy_id ?? ""}`;
}

const columns: readonly ApColumn[] = [
  { key: "point", label: "Point" },
  { key: "condition", label: "Condition" },
  { key: "detail", label: "Detail" },
  { key: "since", label: "Since", mono: true },
  { key: "sample", label: "Last sample", mono: true },
  { key: "value", label: "Value", mono: true },
];

const ago = (iso: string) => formatCountdown(new Date(iso), now.value);

/** "evaluated T+00:12:03" for a ground limit, "entered T+…" for live; the bound when unknown. */
function since(row: PointCondition): string {
  if (!row.evaluated) return "—";
  if (row.entered_at !== null) return ago(row.entered_at);
  return row.entered_at_is_lower_bound ? "before the last 200 evaluations" : "—";
}

/** A critical, caution or stale point washes its row; the mark and word say it too. */
function rowState(row: PointCondition) {
  const state = markState(row);
  return state === "crit" || state === "caution" || state === "stale" ? state : null;
}

const filterOptions = [
  { value: "all", label: "All points" },
  { value: "attention", label: "Needs attention" },
] as const;
</script>

<template>
  <ApPanel index="P1" title="Points" class="min-h-0 flex-1">
    <div class="flex justify-end">
      <ApSegmented v-model="filter" :options="filterOptions" label="Which points" variant="tabs" />
    </div>
    <ApRemote :state="state" loading-label="LOADING POINTS…" @retry="paged.refetch">
      <ApCallout v-if="meta?.telemetry === 'degraded'" tone="caution">
        Last-sample times may be incomplete: the history store did not answer, so a point this node
        has not heard shows its sample time as unknown.
      </ApCallout>
      <ApEmptyState
        v-if="rows.length === 0"
        state="off"
        :headline="filter === 'attention' ? 'No point needs attention' : 'No points to show yet'"
        sentence="Points appear once a limit job has evaluated them or a monitoring rule changed their state."
      />
      <template v-else>
        <p v-if="meta" class="m-0 font-mono text-xs text-text-3 uppercase">
          {{ formatCount(meta.counts.critical) }} critical ·
          {{ formatCount(meta.counts.caution) }} caution ·
          {{ formatCount(meta.counts.stale + meta.counts.unknown) }} stale or unknown ·
          {{ formatCount(meta.counts.not_evaluated) }} not evaluated · stale after
          {{ formatCount(Math.round(meta.stale_after_s / 60)) }} min
        </p>
        <ApTable
          :columns="columns"
          :rows="rows"
          :row-key="rowKey"
          :row-state="rowState"
          caption="Points"
        >
          <template #cell-point="{ row }">
            <RouterLink
              class="text-text-1 underline decoration-border-strong underline-offset-2"
              :to="{ name: 'ops.telemetry', query: { sc: String(sc.scid) } }"
              >{{ row.point_name }}</RouterLink
            >
            <span class="ml-2 font-mono text-xs text-text-3">{{ sourceWords(row) }}</span>
          </template>
          <template #cell-condition="{ row }">
            <ApTag :state="markState(row)" :label="conditionText(row)" />
            <span v-if="freshnessWord(row)" class="ml-2 font-mono text-xs text-text-2">{{
              freshnessWord(row)
            }}</span>
          </template>
          <template #cell-detail="{ row }">{{ detailWords(row) }}</template>
          <template #cell-since="{ row }">{{ since(row) }}</template>
          <template #cell-sample="{ row }">{{
            row.last_sample_at ? ago(row.last_sample_at) : "—"
          }}</template>
          <template #cell-value="{ row }">{{ valueText(row) }}</template>
        </ApTable>
        <div class="flex flex-wrap items-center gap-3">
          <p class="m-0 font-mono text-xs text-text-3 uppercase">
            Showing {{ formatCount(rows.length) }} of {{ formatCount(meta?.counts.total ?? 0) }}
            rows, worst first
          </p>
          <ApButton
            v-if="hasMore"
            size="compact"
            variant="secondary"
            :disabled="paged.moreBusy.value"
            disabled-reason="Loading…"
            @click="paged.more()"
            >Load more</ApButton
          >
          <span role="alert" class="text-sm text-caution-text">{{
            paged.moreError.value ? "More points couldn't load. Try Load more again." : ""
          }}</span>
        </div>
        <p class="m-0 text-sm text-text-3">
          Monitoring rules that have never changed state are not listed until #451.
        </p>
      </template>
    </ApRemote>
  </ApPanel>
</template>
