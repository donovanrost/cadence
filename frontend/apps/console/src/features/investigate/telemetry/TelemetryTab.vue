<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { RouterLink, useRoute, useRouter, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatClock,
  formatRelative,
  useNow,
  ApEmptyState,
  ApField,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApStatusMark,
  ApTable,
  type ApColumn,
} from "@/ui";
import { formatValue, withUnit } from "@/features/alarms/index.ts";
import { fetchPoints, pointLimits } from "@/features/telemetry/index.ts";
import { fetchPasses } from "@/features/contacts/index.ts";
import type { TimeBand } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchHistory } from "../api.ts";
import { RANGES, rangeWindow, toSeries, type RangeKey } from "../model.ts";
import { useSpacecraftTail } from "../tail.ts";
import SampleAside from "../sample/SampleAside.vue";
import { useConsoleWide, useSample } from "../sample/useSample.ts";
import PointPlot from "./PointPlot.vue";
import {
  filterCounts,
  MAX_PLOTTED,
  pointMark,
  pointsFrom,
  toCsv,
  visiblePoints,
  type PointFilter,
} from "./model.ts";

/** Tab · Telemetry (Investigate.md): every value now, and up to 3 plotted. Reads M23/M10/M11/M8. */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);

const points = useRemoteQuery(
  computed(() => ({ m: missionId.value, sc: props.sc.id })),
  (k, signal) => fetchPoints(k.m, { q: "", spacecraftId: k.sc, limit: 200 }, signal),
);
useMissionInvalidation(missionId, ["telemetry", "limits", "catalog"], points.refetch, {
  throttleMs: 10_000,
});
const all = computed(() =>
  points.state.value.status === "ready" ? points.state.value.value.points : [],
);
const q = ref("");
const filter = ref<PointFilter>("all");
const counts = computed(() => filterCounts(all.value));
const chips = computed(() => [
  { value: "out", label: `Out of limits ${counts.value.out}` },
  { value: "stale", label: `Stale ${counts.value.stale}` },
  { value: "all", label: "All" },
]);
const shown = computed(() => visiblePoints(all.value, filter.value, q.value));

/** ?points= and ?range= (ux). */
const pinned = computed(() => pointsFrom(route.query.points));
const range = computed<RangeKey>({
  get: () => (route.query.range === "1h" || route.query.range === "24h" ? route.query.range : "6h"),
  set: (r) => replace({ range: r === "6h" ? undefined : r }),
});
function replace(q2: Record<string, string | undefined>) {
  router
    .replace({ query: { ...route.query, ...q2 } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
function toggle(id: string) {
  const set = pinned.value.includes(id)
    ? pinned.value.filter((p) => p !== id)
    : [...pinned.value, id].slice(0, MAX_PLOTTED);
  replace({ points: set.length ? set.join(",") : undefined, focus: undefined });
}
const plotted = computed(() =>
  pinned.value.flatMap((id) => {
    const p = all.value.find((x) => x.id === id);
    return p ? [p] : [];
  }),
);
const focusId = computed(() => {
  const f = typeof route.query.focus === "string" ? route.query.focus : null;
  return f && pinned.value.includes(f) ? f : (pinned.value[0] ?? null);
});
const focused = computed(() => plotted.value.find((p) => p.id === focusId.value) ?? null);
/** ux U71 A7: ?at= centres the focused point's window on a sample and rings it. */
const at = computed(() => {
  const v = typeof route.query.at === "string" ? Date.parse(route.query.at) : Number.NaN;
  return Number.isNaN(v) ? null : v;
});
/** ux U80: ?sample= opens the Sample aside in T1's place (a sheet below 1100px). */
const wide = useConsoleWide();
const sample = useSample(
  missionId,
  computed(() => props.sc.id),
  focusId,
);
const sampleRead = computed(() => sample.read.state.value);
const sampleTitle = computed(() => {
  const s = sampleRead.value;
  const name = (s.status === "ready" ? s.value.sample?.point_name : null) ?? focused.value?.name;
  return name ? `Sample · ${name}` : "Sample";
});
const atLabel = computed(() => (at.value === null ? null : `${formatClock(new Date(at.value))}Z`));
const today = computed(() => now.value.toISOString().slice(0, 10));
const search = ref<HTMLElement | null>(null);
const searchInput = () => search.value?.querySelector("input") ?? null;
async function closeSample() {
  await sample.close();
  await nextTick();
  searchInput()?.focus();
}
/** "6 h" in sentences (ux review 5); the segmented control keeps its compact labels. */
const rangeLabel = computed(() =>
  (RANGES.find((r) => r.value === range.value)?.label ?? range.value)
    .toLowerCase()
    .replace(/h$/, " h"),
);
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));

/** Pass spans on every plot (kit bands): this spacecraft's passes in the range, by station code. */
const passes = useRemoteQuery(
  computed(() => (pinned.value.length ? `${missionId.value}|${props.sc.id}|${range.value}` : null)),
  (_k, signal) => {
    const w = rangeWindow(range.value, new Date());
    return fetchPasses(
      missionId.value,
      { from: new Date(w.from), to: new Date(w.to), spacecraftId: props.sc.id },
      signal,
    );
  },
);
const passBands = computed<TimeBand[]>(() =>
  passes.state.value.status === "ready"
    ? passes.state.value.value.passes
        .filter((p) => !["canceled", "rejected", "failed"].includes(p.state))
        .map((p) => ({
          from: Date.parse(p.starts_at),
          to: Date.parse(p.ends_at),
          kind: "pass" as const,
          label: p.station.code ?? p.station.name ?? undefined,
        }))
    : [],
);
/** One crosshair time shared by the stacked plots (kit v-model:hover). */
const hoverT = ref<number | null>(null);

/** M8 live tail for the plotted points. */
const tail = useSpacecraftTail(
  missionId,
  computed(() => props.sc.id),
  computed(() => pinned.value),
  () => undefined,
);

/** T3: the focused point's buckets in the range, newest first, and its CSV. */
const values = useRemoteQuery(
  computed(() => (focused.value ? `${focused.value.id}|${range.value}` : null)),
  (_k, signal) => {
    const w = rangeWindow(range.value, new Date());
    return fetchHistory(
      missionId.value,
      focused.value?.id ?? "",
      props.sc.id,
      { from: new Date(w.from), to: new Date(w.to) },
      signal,
    );
  },
);
const valueRows = computed(() =>
  values.state.value.status === "ready"
    ? toSeries(values.state.value.value)
        .sort((a, b) => b.t - a.t)
        .map((r) => ({ ...r, key: String(r.t) }))
    : [],
);
const columns: readonly ApColumn[] = [
  { key: "t", label: "Time", mono: true },
  { key: "mean", label: "Value", mono: true, align: "end" },
  { key: "range", label: "Min – max", mono: true, align: "end" },
];
const csvHref = computed(() =>
  focused.value && valueRows.value.length
    ? `data:text/csv;charset=utf-8,${encodeURIComponent(toCsv(focused.value.id, valueRows.value))}`
    : null,
);
const exploreTo = computed((): RouteLocationRaw => ({
  name: "ops.telemetry",
  query: {
    sc: String(props.sc.scid),
    ...(pinned.value.length ? { p: pinned.value.join(",") } : {}),
    range: range.value,
  },
}));
const latest = (p: (typeof all.value)[number]) =>
  p.latest ? (withUnit(formatValue(p.latest.value), p.unit) ?? "—") : "—";
</script>

<template>
  <ApRemote :state="points.state.value" loading-label="LOADING POINTS…" @retry="points.refetch">
    <ApPanel v-if="all.length === 0" index="T1" title="Points" flush>
      <ApEmptyState
        state="off"
        :headline="`${sc.name} has no telemetry points yet (its profile defines none).`"
      />
    </ApPanel>
    <div
      v-else
      class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[360px_minmax(0,1fr)]"
    >
      <SampleAside
        v-if="sample.open.value && wide"
        wide
        :state="sampleRead"
        :title="sampleTitle"
        :at-label="atLabel"
        :today="today"
        :return-focus="searchInput"
        @close="closeSample"
        @retry="sample.read.refetch"
      />
      <ApPanel v-else index="T1" title="Points" :meta="`${all.length}`" pane flush>
        <div ref="search" class="flex flex-col gap-2 border-b border-hairline px-4 py-3">
          <ApField v-model="q" label="Search points" hidden-label placeholder="Label or key" />
          <ApSegmented v-model="filter" :options="chips" label="Show" variant="micro" />
        </div>
        <ul class="m-0 list-none p-0">
          <li
            v-for="p in shown"
            :key="p.id"
            class="flex items-start gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
          >
            <input
              :id="`pt-${p.id}`"
              type="checkbox"
              class="mt-1 max-md:hidden"
              :checked="pinned.includes(p.id)"
              :disabled="!pinned.includes(p.id) && pinned.length >= MAX_PLOTTED"
              :title="
                !pinned.includes(p.id) && pinned.length >= MAX_PLOTTED
                  ? 'Plot up to 3 points'
                  : undefined
              "
              @change="toggle(p.id)"
            />
            <ApStatusMark :state="pointMark(p)" class="mt-1" />
            <label :for="`pt-${p.id}`" class="min-w-0 flex-1 cursor-pointer">
              <span class="block font-semibold text-readout">{{ p.name }}</span>
              <span class="block font-mono text-xs text-text-3">{{ p.id }}</span>
            </label>
            <span class="text-right font-mono text-sm">
              <span v-if="p.latest" class="block text-readout">{{ latest(p) }}</span>
              <!-- ux #10: null can mean "not in the read's window", so never claim "yet". -->
              <span v-else class="block text-text-3">No recent value</span>
              <span v-if="p.latest?.received_at" class="block text-xs text-text-3">{{
                formatRelative(new Date(p.latest.received_at), now)
              }}</span>
              <span
                v-if="pointLimits(p).word"
                class="block text-xs text-text-3"
                :title="pointLimits(p).title ?? undefined"
                >{{ pointLimits(p).word }}</span
              >
            </span>
          </li>
        </ul>
      </ApPanel>
      <div class="flex min-h-0 flex-col gap-3 max-md:hidden">
        <ApPanel
          index="T2"
          :title="`Plot · ${plotted.length || 'no'} ${plotted.length === 1 ? 'point' : 'points'}`"
          flush
        >
          <template #meta>
            <span class="flex items-center gap-3">
              <ApSegmented v-model="range" :options="ranges" label="Range" variant="micro" />
              <RouterLink
                :to="exploreTo"
                class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
                >Open in Explore</RouterLink
              >
              <RouterLink
                :to="{ name: 'ops.dashboards' }"
                class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
                >Dashboards</RouterLink
              >
            </span>
          </template>
          <ApEmptyState
            v-if="plotted.length === 0"
            state="off"
            headline="Tick up to 3 points to plot them."
          />
          <div v-else class="flex flex-col gap-2 p-3">
            <!-- 2–3 points: stacked small multiples on one time axis, never two y-axes (ux). -->
            <div
              v-for="p in plotted"
              :key="p.id"
              class="cursor-pointer"
              :class="p.id === focusId ? 'outline outline-1 outline-hairline' : ''"
              @click="replace({ focus: p.id })"
            >
              <p class="m-0 px-1 font-mono text-xs text-text-3 uppercase">
                {{ p.name }}{{ p.unit ? ` · ${p.unit}` : "" }}
              </p>
              <PointPlot
                :mission-id="missionId"
                :spacecraft-id="sc.id"
                :point="p"
                :range="range"
                :range-label="rangeLabel"
                :tail="tail.tails.value.get(p.id) ?? []"
                :height="plotted.length === 1 ? 220 : 120"
                :bands="passBands"
                :at="p.id === focusId ? at : null"
                v-model:hover="hoverT"
              />
            </div>
          </div>
        </ApPanel>
        <ApPanel
          v-if="focused"
          index="T3"
          :title="`Values · ${focused.name}`"
          meta="newest first · per plot bucket"
          pane
          flush
        >
          <template #meta>
            <a
              v-if="csvHref"
              :href="csvHref"
              :download="`${sc.name}-${focused.id}.csv`"
              class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
              >Export CSV</a
            >
          </template>
          <ApRemote
            :state="values.state.value"
            loading-label="LOADING VALUES…"
            @retry="values.refetch"
          >
            <ApEmptyState
              v-if="valueRows.length === 0"
              state="off"
              :headline="`No samples in the last ${rangeLabel}.`"
            />
            <ApTable
              v-else
              :columns="columns"
              :rows="valueRows"
              :row-key="(r) => r.key"
              caption="Values"
            >
              <template #cell-t="{ row }"
                >{{ new Date(row.t).toISOString().slice(5, 19).replace("T", " ") }}Z</template
              >
              <template #cell-mean="{ row }">{{
                withUnit(formatValue(row.mean), focused.unit)
              }}</template>
              <template #cell-range="{ row }"
                >{{ formatValue(row.min) }} – {{ formatValue(row.max) }}</template
              >
            </ApTable>
          </ApRemote>
        </ApPanel>
      </div>
    </div>
    <SampleAside
      v-if="sample.open.value && !wide"
      :wide="false"
      :state="sampleRead"
      :title="sampleTitle"
      :at-label="atLabel"
      :today="today"
      :return-focus="searchInput"
      @close="closeSample"
      @retry="sample.read.refetch"
    />
  </ApRemote>
</template>
