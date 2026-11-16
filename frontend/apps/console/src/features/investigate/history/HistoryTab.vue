<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink, useRoute, useRouter, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatClock,
  formatRelative,
  useNow,
  ApEmptyState,
  ApListRow,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApTag,
  type TimeBand,
} from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchHistory, fetchLimitIntervals } from "../api.ts";
import { limitSegments, toSeries, trendSentence } from "../model.ts";
import TrendBlock from "../TrendBlock.vue";
import { sampleLink } from "../sample/link.ts";
import {
  conditionLine,
  durationWords,
  fetchEpisodeHistory,
  fetchEpisodeList,
  occurrenceSummary,
  peakFrom,
  shortTime,
  sourceTag,
  valueWords,
  type Occurrence,
} from "./api.ts";
import OccurrencesTable from "./OccurrencesTable.vue";

/** Tab · History (Investigate.md): has this happened before, and how did it end? */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);

const list = useRemoteQuery(
  computed(() => ({ m: missionId.value, sc: props.sc.id })),
  (k, signal) => fetchEpisodeList(k.m, k.sc, signal),
);
const items = computed(() =>
  list.state.value.status === "ready" ? list.state.value.value.items : [],
);
/** ?episode=, else the active episode, else the most recent (ux). */
const selected = computed<Occurrence | null>(() => {
  const id = typeof route.query.episode === "string" ? route.query.episode : null;
  return (
    items.value.find((o) => o.id === id) ??
    items.value.find((o) => o.cleared_at === null) ??
    items.value[0] ??
    null
  );
});
function select(id: string) {
  router
    .replace({ query: { ...route.query, episode: id } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}

/** Counts strip: the server's counts when sent, else counted from the 90-day list. */
const counts = computed(() => {
  const s = list.state.value;
  if (s.status !== "ready") return null;
  const v = s.value;
  const retention = v.retention_days;
  return [7, 30, 90].map((days) => {
    const key = `d${days}` as "d7" | "d30" | "d90";
    if (retention !== null && retention < days)
      return { days, text: "—", note: `kept for ${retention} days` };
    return { days, text: String(v.counts[key]), note: null };
  });
});

/** H2 window: 2 h before it opened to 2 h after it cleared (or now). */
const windowOf = (o: Occurrence) => ({
  from: new Date(Date.parse(o.opened_at) - 2 * 3_600_000),
  to: new Date(
    Math.min((o.cleared_at ? Date.parse(o.cleared_at) : Date.now()) + 2 * 3_600_000, Date.now()),
  ),
});
const chartKey = computed(() =>
  selected.value ? `${selected.value.id}|${selected.value.cleared_at ?? "open"}` : null,
);
const history = useRemoteQuery(chartKey, (_k, signal) => {
  const o = selected.value;
  if (!o)
    return Promise.resolve({
      ok: false as const,
      error: { kind: "malformed" as const, message: "no episode" },
    });
  return fetchHistory(missionId.value, o.point.id, props.sc.id, windowOf(o), signal);
});
const intervals = useRemoteQuery(chartKey, (_k, signal) => {
  const o = selected.value;
  if (!o)
    return Promise.resolve({
      ok: false as const,
      error: { kind: "malformed" as const, message: "no episode" },
    });
  return fetchLimitIntervals(missionId.value, o.point.id, props.sc.id, windowOf(o), signal);
});
const view = computed(() => {
  const h = history.state.value;
  const o = selected.value;
  if (h.status !== "ready" || !o) return null;
  const window = { from: Date.parse(h.value.from), to: Date.parse(h.value.to) };
  const series = toSeries(h.value);
  const i = intervals.state.value;
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, null);
  return {
    window,
    series,
    limits,
    stepMs: h.value.bucket_width_ms,
    sentence: trendSentence(o.point.name, "episode window", series, limits),
  };
});
/** H2: the episode's own span, shaded with its severity (kit fcae7025). */
const episodeBand = computed<TimeBand[]>(() => {
  const o = selected.value;
  if (!o) return [];
  return [
    {
      from: Date.parse(o.opened_at),
      to: o.cleared_at ? Date.parse(o.cleared_at) : now.value.getTime(),
      kind: "episode",
      severity: o.severity === "critical" ? "crit" : "caution",
      label: o.cleared_at ? undefined : "Open",
    },
  ];
});
const peakMeta = computed(() => {
  const o = selected.value;
  const v = view.value;
  if (!o || !v) return undefined;
  const p = peakFrom(o, v.series, now.value.getTime());
  return p
    ? `Peak ${valueWords(p.value, o.point.unit)} · ${shortTime(new Date(p.t).toISOString())}`
    : undefined;
});
/** ux U71: H2 rings the selected episode's triggering sample, when the read carries it. */
const triggerMarks = computed(() => {
  const t = selected.value?.trigger;
  return t?.sample_id
    ? [{ t: Date.parse(t.at), label: `the sample that raised it, ${formatClock(new Date(t.at))}Z` }]
    : [];
});
/** ux U80: H2's line opens the Sample aside on the trigger, as B1's does (no per-row links). */
const sampleTo = computed(() => {
  const o = selected.value;
  const t = o?.trigger;
  return o && t?.sample_id
    ? sampleLink(props.sc.scid, o.point.id, { ...t, id: t.sample_id })
    : null;
});
const telemetryTo = computed((): RouteLocationRaw | null => {
  const o = selected.value;
  if (!o) return null;
  const w = windowOf(o);
  return {
    name: "ops.telemetry",
    query: {
      sc: String(props.sc.scid),
      p: o.point.id,
      from: w.from.toISOString(),
      to: w.to.toISOString(),
    },
  };
});

/** H3: This alarm │ All conditions on <point>. */
const scopeChoice = ref<"alarm" | "point">("alarm");
const occurrences = useRemoteQuery(
  computed(() => (selected.value ? `${selected.value.id}|${scopeChoice.value}` : null)),
  (k, signal) => {
    const [id = "", sc = "alarm"] = k.split("|");
    return fetchEpisodeHistory(missionId.value, id, sc === "point" ? "point" : "alarm", signal);
  },
);
const summary = computed(() =>
  occurrenceSummary(
    occurrences.state.value.status === "ready" ? occurrences.state.value.value : null,
  ),
);
const live = (o: Occurrence) => `OPEN · ${formatRelative(new Date(o.opened_at), now.value)}`;
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3">
    <p class="m-0 flex flex-wrap items-baseline gap-x-4 font-mono text-xs text-text-3 uppercase">
      <span>Alarm episodes</span>
      <span v-for="c in counts ?? []" :key="c.days"
        >{{ c.days }} days <span class="text-readout">{{ c.text }}</span
        ><span v-if="c.note" class="normal-case"> ({{ c.note }})</span></span
      >
      <RouterLink
        :to="{ name: 'ops.timeline', query: { sc: String(sc.scid) } }"
        class="max-md:hit-44 ml-auto text-text-3 normal-case no-underline hover:text-readout hover:underline"
        >Everything on {{ sc.name }} → Timeline</RouterLink
      >
    </p>
    <ApRemote :state="list.state.value" loading-label="LOADING EPISODES…" @retry="list.refetch">
      <ApPanel v-if="items.length === 0" index="H1" title="Episodes" flush>
        <ApEmptyState
          state="off"
          :headline="`No alarm episodes on ${sc.name} in the last 90 days.`"
        />
      </ApPanel>
      <div
        v-else
        class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[360px_minmax(0,1fr)]"
      >
        <ApPanel index="H1" title="Episodes" meta="newest first" pane flush>
          <ul class="m-0 list-none p-0">
            <ApListRow
              v-for="o in items"
              :key="o.id"
              :state="o.severity === 'critical' ? 'crit' : 'caution'"
              :sentence="`${shortTime(o.opened_at)} · ${durationWords(o) ?? live(o)}`"
              :meta="
                o.acknowledged_by?.name ? `Ack ${o.acknowledged_by.name}`.toUpperCase() : undefined
              "
            >
              <template #title>
                <button
                  type="button"
                  class="max-md:hit-44 cursor-pointer text-left text-readout hover:underline"
                  :class="o.id === selected?.id ? 'font-semibold underline' : ''"
                  :aria-current="o.id === selected?.id ? 'true' : undefined"
                  @click="select(o.id)"
                >
                  {{ conditionLine(o) }}
                </button>
                <ApTag class="ml-2" :label="sourceTag(o)" />
              </template>
            </ApListRow>
          </ul>
        </ApPanel>
        <div v-if="selected" class="flex min-h-0 flex-col gap-3">
          <ApPanel
            index="H2"
            :title="conditionLine(selected)"
            :meta="peakMeta"
            flush
            class="flex-none"
          >
            <template #meta>
              <RouterLink
                v-if="telemetryTo"
                :to="telemetryTo"
                class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
                >Open in Telemetry →</RouterLink
              >
            </template>
            <div class="p-3">
              <TrendBlock
                :point-name="selected.point.name"
                :unit="selected.point.unit"
                range-label="episode window"
                :history="history.state.value"
                :view="view"
                :height="180"
                :bands="episodeBand"
                :marks="triggerMarks"
                @retry="history.refetch"
              />
              <p v-if="sampleTo && selected.trigger" class="m-0 pt-2 text-sm">
                <RouterLink :to="sampleTo" class="text-readout hover:underline"
                  >Show the sample that raised it ({{
                    formatClock(new Date(selected.trigger.at))
                  }}Z)</RouterLink
                >
              </p>
            </div>
          </ApPanel>
          <ApPanel index="H3" title="Prior occurrences" :meta="summary ?? undefined" pane flush>
            <div class="flex items-center justify-end border-b border-hairline px-4 py-2">
              <ApSegmented
                v-model="scopeChoice"
                :options="[
                  { value: 'alarm', label: 'This alarm' },
                  { value: 'point', label: `All conditions on ${selected.point.name}` },
                ]"
                label="Which occurrences"
                variant="micro"
              />
            </div>
            <ApRemote
              :state="occurrences.state.value"
              loading-label="LOADING OCCURRENCES…"
              @retry="occurrences.refetch"
            >
              <template #default="{ value }">
                <ApEmptyState
                  v-if="value.items.length === 0"
                  state="off"
                  headline="No earlier occurrences in the last 90 days."
                />
                <OccurrencesTable v-else :items="value.items" />
              </template>
            </ApRemote>
          </ApPanel>
        </div>
      </div>
    </ApRemote>
  </div>
</template>
