<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApPageHeader, ApRemote, type TimeRange } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import { fetchLimitIntervals } from "@/features/investigate/index.ts";
import { resolveWindow, windowFromRange, windowLabel, type WindowSel } from "./window.ts";
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
  return only && sc
    ? JSON.stringify({ m: missionId.value, p: only.pointId, sc: sc.id, w: selection.value.window })
    : null;
});
const intervals = useRemoteQuery(single, (k, signal) => {
  // Sound: produced by JSON.stringify above.
  const { m, p, sc, w } = JSON.parse(k) as { m: string; p: string; sc: string; w: WindowSel };
  const r = resolveWindow(w, new Date());
  return fetchLimitIntervals(m, p, sc, { from: new Date(r.from), to: new Date(r.to) }, signal);
});

const view = computed(() => {
  const s = data.state.value;
  const i = intervals.state.value;
  return s.status === "ready" ? plotView(s.value, i.status === "ready" ? i.value : null) : null;
});
const rows = computed(() =>
  data.state.value.status === "ready" ? latestRows(data.state.value.value) : [],
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · telemetry`" title="Explore">
      <ApButton size="compact" variant="ghost" :to="{ name: 'ops.dashboards' }"
        >Dashboards ↗</ApButton
      >
    </ApPageHeader>
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <div
        class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[320px_minmax(0,1fr)]"
      >
        <PointsPanel
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
            @retry="data.refetch"
          />
          <ValuesTable v-if="rows.length" :rows="rows" />
        </div>
      </div>
    </ApRemote>
  </div>
</template>
