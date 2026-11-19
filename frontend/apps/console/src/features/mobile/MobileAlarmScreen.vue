<script setup lang="ts">
import { scidParam } from "@/api/index.ts";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope, useMobileHeader } from "@/shell";
import {
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApRemote,
  formatCountdown,
  formatRelative,
  useNow,
} from "@/ui";
import { conditionWords, crossedCondition, episodeFor } from "@/features/alarms/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import {
  DEFAULT_RANGE,
  limitSegments,
  pickAlarm,
  RANGES,
  ratePerHour,
  toSeries,
  trendSentence,
  EpisodeBar,
  useEpisodeDetail,
  usePointTrend,
  useSpacecraftAlarms,
  useSpacecraftEpisodes,
  usePointAlarms,
  sisters as sistersOf,
} from "@/features/investigate/index.ts";
import MobileAlarmPanel from "./MobileAlarmPanel.vue";
import YourGoBlock from "./YourGoBlock.vue";

/**
 * J6 paged view (Mobile.md), the ops.spacecraft route under 768px: is this real? Alarm, its trend
 * and timing first, then "Your GO is requested" when a request awaiting your GO targets it, then
 * Acknowledge / Hand off (fe-ops' EpisodeBar, stacked).
 */
const route = useRoute("ops.spacecraft");
const scope = useMissionScope();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
const scid = computed(() => scidParam(route.params.scId));
const sc = computed(() => {
  const f = fleet.state.value;
  return f.status === "ready"
    ? (f.value.spacecraft.find((row) => row.scid === scid.value) ?? null)
    : null;
});
const alarms = useSpacecraftAlarms(
  missionId,
  computed(() => sc.value?.id ?? null),
);
const alarm = computed(() => {
  const a = alarms.state.value;
  const id = typeof route.query.alarm === "string" ? route.query.alarm : null;
  return a.status === "ready" ? pickAlarm(a.value.alarms, id) : null;
});

/** The lifecycle episode behind the shown alarm (Acknowledge / Hand off; Mobile.md §4). */
const episodes = useSpacecraftEpisodes(
  missionId,
  computed(() => sc.value?.id ?? null),
);
const episodeId = computed(() => {
  const s = episodes.state.value;
  return s.status === "ready" && alarm.value && sc.value
    ? (episodeFor(s.value.episodes, sc.value.id, alarm.value.point.id)?.id ?? null)
    : null;
});
const detail = useEpisodeDetail(missionId, episodeId);
const episode = computed(() =>
  episodeId.value && detail.state.value.status === "ready" ? detail.state.value.value : null,
);
const permissions = computed(() =>
  episodes.state.value.status === "ready" ? episodes.state.value.value.permissions : [],
);
function refreshEpisode() {
  episodes.refetch();
  detail.refetch();
}

/**
 * Mobile.md §1's "3 sisters in P07 …": same plane, same point out of limits now (B4's v1 rule).
 * It says "out of limits", not "trending": nothing here computes a trend across sisters.
 */
const pointAlarms = usePointAlarms(
  missionId,
  computed(() => (sc.value?.plane == null ? null : (alarm.value?.point.id ?? null))),
);
const sisterLine = computed(() => {
  const s = pointAlarms.state.value;
  const f = fleet.state.value;
  const me = sc.value;
  const a = alarm.value;
  if (s.status !== "ready" || f.status !== "ready" || !me || !a || me.plane === null) return null;
  const n = sistersOf(s.value.alarms, f.value.spacecraft, me, a.point.id).length;
  const plane = `P${String(me.plane).padStart(2, "0")}`;
  return n === 0 ? null : `${n} ${n === 1 ? "sister" : "sisters"} in ${plane} out of limits`;
});
const range = computed(() => DEFAULT_RANGE);
const rangeLabel = RANGES.find((r) => r.value === DEFAULT_RANGE)?.label ?? DEFAULT_RANGE;
const trend = usePointTrend(
  missionId,
  computed(() => sc.value?.id ?? null),
  computed(() => alarm.value?.point.id ?? null),
  range,
);
const view = computed(() => {
  const h = trend.history.state.value;
  const a = alarm.value;
  if (h.status !== "ready" || !a) return null;
  const window = { from: Date.parse(h.value.from), to: Date.parse(h.value.to) };
  const i = trend.intervals.state.value;
  const series = toSeries(h.value);
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, a.thresholds);
  return {
    window,
    series,
    limits,
    stepMs: h.value.bucket_width_ms,
    rate: ratePerHour(series, h.value.bucket_width_ms),
    sentence: trendSentence(a.point.name, rangeLabel, series, limits),
  };
});

useMobileHeader(() => {
  const a = alarm.value;
  const since = a?.first_crossed_at
    ? ` ${formatRelative(new Date(a.first_crossed_at), now.value)}`
    : "";
  return {
    title: a
      ? `${a.point.subsystem ?? "Point"} ${conditionWords(crossedCondition(a)) ?? "out of limits"}`
      : (sc.value?.name ?? "Spacecraft"),
    context: `${a ? `Alarm${since}` : "Spacecraft"} · ${scope.value.mission.name}`,
    back: { name: "ops.alarms" },
  };
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <template v-if="sc">
        <ApRemote
          :state="alarms.state.value"
          loading-label="LOADING ALARM…"
          @retry="alarms.refetch"
        >
          <MobileAlarmPanel
            v-if="alarm"
            :sc="sc"
            :alarm="alarm"
            :history="trend.history.state.value"
            :view="view"
            :range-label="rangeLabel"
            :sisters="sisterLine"
            @retry="trend.history.refetch"
          />
          <template v-else>
            <h1 class="m-0 font-display text-[22px] font-bold tracking-id uppercase">
              {{ sc.name }}
            </h1>
            <ApCallout tone="nominal"
              >No active alarm on {{ sc.name }}. It may have cleared since you were
              paged.</ApCallout
            >
          </template>
        </ApRemote>
        <ApPanel index="T" title="Timing" flush>
          <p v-if="sc.in_contact" class="m-0 px-4 py-3 font-mono text-[28px] text-readout">
            In contact
          </p>
          <div v-else-if="sc.next_aos_at" class="flex flex-col gap-1 px-4 py-3">
            <span class="ap-label">Next AOS</span>
            <span class="font-mono text-[28px] text-readout tabular">{{
              formatCountdown(new Date(sc.next_aos_at), now)
            }}</span>
          </div>
          <ApEmptyState
            v-else
            state="off"
            headline="No pass booked"
            sentence="No upcoming contact is booked for this spacecraft. Check Contacts on a desktop."
          />
        </ApPanel>
        <YourGoBlock :mission-id="missionId" :spacecraft-id="sc.id" />
        <EpisodeBar
          v-if="episode"
          :episode="episode"
          :permissions="permissions"
          layout="stacked"
          @changed="refreshEpisode"
        />
      </template>
      <template v-else>
        <h1 class="m-0 font-display text-[22px] font-bold tracking-id uppercase">
          Spacecraft not found
        </h1>
        <ApCallout tone="caution"
          >No spacecraft with SCID {{ route.params.scId }} in {{ scope.mission.name }}.</ApCallout
        >
      </template>
    </ApRemote>
    <p class="m-0 pt-2 text-center font-mono text-xs text-text-4 uppercase">
      New uplink sequences are desktop only, by design
    </p>
  </div>
</template>
