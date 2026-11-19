<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { ApKeyValue } from "@/ui";
import { episodeFor, fetchEpisodes, type Alarms } from "@/features/alarms/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import AlarmTrendPanel from "./AlarmTrendPanel.vue";
import EventLogPanel from "./EventLogPanel.vue";
import EpisodeBar from "./EpisodeBar.vue";
import SistersPanel from "./SistersPanel.vue";
import { logLines } from "./eventLog.ts";
import { sampleLink } from "./sample/link.ts";
import { useEpisodeDetail, useSpacecraftEpisodes, useSpacecraftEvents } from "./useInvestigate.ts";
import { DEFAULT_RANGE, lastCleared, pickAlarm, type RangeKey } from "./model.ts";

/** J2 · Investigate tab: B1 trend, B2 events, B4 same point in limits, technical details. */
const props = defineProps<{
  sc: FleetSpacecraft;
  fleet: readonly FleetSpacecraft[];
  alarms: RemoteState<Alarms>;
  limitsConfigured: boolean;
}>();
defineEmits<{ retry: [] }>();
const route = useRoute();
const range = ref<RangeKey>(DEFAULT_RANGE);

const alarm = computed(() => {
  const state = props.alarms;
  const id = typeof route.query.alarm === "string" ? route.query.alarm : null;
  const point = typeof route.query.point === "string" ? route.query.point : null;
  return state.status === "ready" ? pickAlarm(state.value.alarms, id, point) : null;
});

const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const episodes = useSpacecraftEpisodes(
  missionId,
  computed(() => props.sc.id),
);
/** The lifecycle episode behind the shown alarm (same spacecraft and point). */
const episodeId = computed(() => {
  const s = episodes.state.value;
  return s.status === "ready" && alarm.value
    ? (episodeFor(s.value.episodes, props.sc.id, alarm.value.point.id)?.id ?? null)
    : null;
});
const detail = useEpisodeDetail(missionId, episodeId);
const episode = computed(() =>
  episodeId.value && detail.state.value.status === "ready" ? detail.state.value.value : null,
);
/** §B1: with no active alarm, the latest cleared one shows "back in limits" (read only then). */
const clearedRead = useRemoteQuery(
  computed(() =>
    props.alarms.status === "ready" && alarm.value === null
      ? { m: missionId.value, sc: props.sc.id }
      : null,
  ),
  (k, signal) => fetchEpisodes(k.m, { spacecraftId: k.sc, state: "cleared" }, signal),
);
useMissionInvalidation(missionId, ["alarms"], clearedRead.refetch);
const resolved = computed(() =>
  alarm.value === null && clearedRead.state.value.status === "ready"
    ? lastCleared(clearedRead.state.value.value.episodes)
    : null,
);
const permissions = computed(() =>
  episodes.state.value.status === "ready" ? episodes.state.value.value.permissions : [],
);
const events = useSpacecraftEvents(
  missionId,
  computed(() => props.sc.id),
);
const lines = computed(() =>
  logLines(
    events.state.value.status === "ready" ? events.state.value.value.events : null,
    episode.value
      ? {
          pointId: episode.value.point.id,
          openedAt: episode.value.opened_at,
          clearedAt: episode.value.cleared_at,
          events: episode.value.events,
        }
      : null,
    // ux U71 A7 / U80: 'Show sample' opens Telemetry on the alarm's point, centred and ringed,
    // with the Sample aside open on it.
    (s) => (episode.value ? sampleLink(props.sc.scid, episode.value.point.id, s) : null),
  ),
);
function refreshEpisode() {
  episodes.refetch();
  detail.refetch();
}

const details = computed(() => [
  { key: "sc", label: "Spacecraft id", value: props.sc.id, mono: true },
  ...(props.sc.profile
    ? [{ key: "profile", label: "Profile id", value: props.sc.profile.id, mono: true }]
    : []),
  ...(alarm.value
    ? [
        { key: "point", label: "Point id", value: alarm.value.point.id, mono: true },
        { key: "alarm", label: "Alarm id", value: alarm.value.id, mono: true },
      ]
    : []),
]);
</script>

<template>
  <div
    class="grid grid-cols-1 gap-2.5 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_380px]"
  >
    <div class="flex flex-col gap-2.5 console:min-h-0">
      <AlarmTrendPanel
        v-model:range="range"
        :sc="sc"
        :alarms="alarms"
        :limits-configured="limitsConfigured"
        :alarm="alarm"
        :episode="episode"
        :resolved="resolved"
        @retry="$emit('retry')"
      >
        <template v-if="episode" #lifecycle>
          <EpisodeBar :episode="episode" :permissions="permissions" @changed="refreshEpisode" />
        </template>
      </AlarmTrendPanel>
      <EventLogPanel
        class="min-h-[120px] flex-1"
        :state="events.state.value"
        :lines="lines"
        :scid="sc.scid"
        @retry="events.refetch"
      />
    </div>
    <aside class="flex flex-col gap-2.5 console:min-h-0" aria-label="Context">
      <SistersPanel class="min-h-[120px] flex-1" :sc="sc" :fleet="fleet" :alarm="alarm" />
      <details class="flex-none border border-hairline bg-panel px-4 py-2.5">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <div class="pt-2.5"><ApKeyValue :items="details" /></div>
      </details>
    </aside>
  </div>
</template>
