<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApPageHeader, ApRemote, type TimeRange } from "@/ui";
import { TelemetryTabs } from "@/features/dashboards/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import { fetchLimitIntervals } from "@/features/investigate/index.ts";
import { resolveWindow, windowFromRange, windowLabel } from "./window.ts";
import PlotPanel from "./PlotPanel.vue";
import PointsPanel from "./PointsPanel.vue";
import ValuesTable from "./ValuesTable.vue";
import { latestRows, plotView } from "./plot.ts";
import {
  addTo,
  parseSelection,
  removeFrom,
  selectionQuery,
  seriesOf,
  type Selection,
} from "./selection.ts";
import { useSeries } from "./useSeries.ts";
import { useRecentPlots } from "./recent.ts";

/** Telemetry explore (OpsLists §Telemetry): plot points for spacecraft over a window. */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);

const selection = computed(() => parseSelection(route.query));
const picked = computed(() => seriesOf(selection.value));
/** The empty state's three suggestions: the spacecraft × points you plotted most recently. */
const recent = useRecentPlots(missionId, selection, fleetRows);
function update(patch: Partial<Selection>) {
  router
    .replace({ query: selectionQuery({ ...selection.value, ...patch }, route.query) })
    .catch((error: unknown) => console.error("Navigation failed", error));
}
/**
 * The picker's window. `new Date()` is read without reactivity on purpose: the value only changes
 * with the selection, so a preset doesn't rewrite the picker's fields every clock tick.
 */
const window = computed<TimeRange>({
  get: () => resolveWindow(selection.value.window, new Date()),
  set: (r) => update({ window: windowFromRange(r, new Date()) }),
});

const data = useSeries(
  missionId,
  computed(() => picked.value.series),
  fleetRows,
  computed(() => selection.value.window),
);

/** Limit bands only for a single plotted point on a single spacecraft. */
const single = computed(() => {
  const only = picked.value.series.length === 1 ? picked.value.series[0] : undefined;
  const sc = only ? fleetRows.value.find((row) => row.scid === only.scid) : undefined;
  // A typed key: useRemoteQuery compares keys by value (typing §12 A4).
  return only && sc
    ? { m: missionId.value, p: only.pointId, sc: sc.id, w: selection.value.window }
    : null;
});
const intervals = useRemoteQuery(single, (k, signal) => {
  const r = resolveWindow(k.w, new Date());
  return fetchLimitIntervals(
    k.m,
    k.p,
    k.sc,
    { from: new Date(r.from), to: new Date(r.to) },
    signal,
  );
});

const view = computed(() => {
  const s = data.state.value;
  const i = intervals.state.value;
  return s.status === "ready" ? plotView(s.value, i.status === "ready" ? i.value : null) : null;
});
/** D12 (ux): points with no spacecraft (a redirected bookmark) ask for one, focus on the picker. */
const noSc = computed(() => (selection.value.scids.length === 0 ? selection.value.points : []));
const points = ref<{ focusSpacecraft: () => void } | null>(null);
watch(
  () => noSc.value.length > 0 && fleet.state.value.status === "ready",
  (ask) => {
    if (ask) points.value?.focusSpacecraft();
  },
  { flush: "post", immediate: true },
);
const rows = computed(() =>
  data.state.value.status === "ready" ? latestRows(data.state.value.value) : [],
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · telemetry`" title="Explore" />
    <TelemetryTabs active="explore" />
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <div
        class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[320px_minmax(0,1fr)]"
      >
        <PointsPanel
          ref="points"
          class="max-console:min-h-[320px]"
          :fleet="fleetRows"
          :scids="selection.scids"
          :points="selection.points"
          @add-sc="(scid) => update({ scids: addTo(selection.scids, scid) })"
          @remove-sc="(scid) => update({ scids: removeFrom(selection.scids, scid) })"
          @add-point="(p) => update({ points: addTo(selection.points, p) })"
          @remove-point="(p) => update({ points: removeFrom(selection.points, p) })"
        />
        <div class="flex flex-col gap-3 console:min-h-0">
          <PlotPanel
            v-model:window="window"
            :window-label="windowLabel(selection.window)"
            class="min-h-[360px] flex-1"
            :state="data.state.value"
            :view="view"
            :empty="picked.series.length === 0"
            :dropped="picked.dropped"
            :suggested="recent.suggested.value"
            :points-without-sc="noSc"
            :refresh-failed="data.refreshFailed.value"
            @retry="data.refetch"
            @pick-sc="points?.focusSpacecraft()"
            @suggest="
              (r) =>
                update({
                  scids: addTo(selection.scids, r.scid),
                  points: addTo(selection.points, r.point),
                })
            "
          />
          <ValuesTable v-if="rows.length" :rows="rows" />
        </div>
      </div>
    </ApRemote>
  </div>
</template>
