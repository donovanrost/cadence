<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented } from "@/ui";
import { RANGES, rangeWindow, type RangeKey } from "@/features/investigate/index.ts";
import { eventKinds, fetchDensity, fetchEvents, type EventKind } from "./api.ts";
import KindToggles from "./KindToggles.vue";
import DensityStrip from "./DensityStrip.vue";
import EventLog from "./EventLog.vue";
import { densityBucketS } from "./model.ts";

/** Timeline (OpsLists §Timeline): fleet-wide events, newest first, with a density strip. */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);

const range = computed<RangeKey>({
  get: () => (route.query.range === "1h" || route.query.range === "6h" ? route.query.range : "24h"),
  set: (r) => {
    router
      .replace({ query: { ...route.query, range: r === "24h" ? undefined : r } })
      .catch((e: unknown) => console.error("Navigation failed", e));
  },
});
const title = computed(
  () => `Last ${RANGES.find((r) => r.value === range.value)?.label ?? range.value}`,
);
/** Selected kinds from ?kind=limit,command (none = all). */
const kinds = computed<EventKind[]>(() => {
  const raw = typeof route.query.kind === "string" ? route.query.kind.split(",") : [];
  return eventKinds.filter((k) => raw.includes(k));
});
function setKinds(next: EventKind[]) {
  router
    .replace({ query: { ...route.query, kind: next.length ? next.join(",") : undefined } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
const key = computed(() => JSON.stringify({ m: missionId.value, r: range.value, k: kinds.value }));
type Key = { m: string; r: RangeKey; k: EventKind[] };
const windowOf = (r: RangeKey) => {
  const w = rangeWindow(r, new Date());
  return { from: new Date(w.from), to: new Date(w.to) };
};
// Sound: keys are produced by JSON.stringify(Key) above.
const events = useRemoteQuery(key, (k, signal) => {
  const { m, r, k: only } = JSON.parse(k) as Key;
  return fetchEvents(m, { ...windowOf(r), kinds: only }, signal);
});
const density = useRemoteQuery(key, (k, signal) => {
  const { m, r, k: only } = JSON.parse(k) as Key;
  const w = windowOf(r);
  return fetchDensity(
    m,
    { ...w, kinds: only },
    densityBucketS(w.to.getTime() - w.from.getTime()),
    signal,
  );
});
useMissionInvalidation(missionId, ["events", "alarms"], () => {
  events.refetch();
  density.refetch();
});

const missing = computed(
  () => events.state.value.status === "failed" && events.state.value.error.kind === "not_found",
);
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · timeline`" :title="title">
      <ApSegmented v-model="range" :options="ranges" label="Window" variant="micro" />
    </ApPageHeader>
    <KindToggles class="flex-none" :selected="kinds" @change="setKinds" />
    <ApPanel v-if="missing" index="E2" title="Event log" flush>
      <ApEmptyState
        state="off"
        headline="Event log not available yet"
        sentence="The mission events read isn't connected to this console."
      />
    </ApPanel>
    <template v-else>
      <div
        v-if="density.state.value.status === 'ready' && events.state.value.status === 'ready'"
        class="flex-none"
      >
        <DensityStrip
          :density="density.state.value.value"
          :window="{
            from: Date.parse(events.state.value.value.from),
            to: Date.parse(events.state.value.value.to),
          }"
          :now="now.getTime()"
        />
      </div>
      <ApPanel index="E2" title="Event log" pane flush class="console:min-h-0 console:flex-1">
        <ApRemote
          :state="events.state.value"
          loading-label="LOADING EVENTS…"
          @retry="events.refetch"
        >
          <template #default="{ value }">
            <ApEmptyState
              v-if="value.events.length === 0"
              :headline="`No events in the ${title.toLowerCase()}`"
            />
            <EventLog v-else :events="value.events" />
          </template>
        </ApRemote>
      </ApPanel>
    </template>
  </div>
</template>
