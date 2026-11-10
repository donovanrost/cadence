<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented, ApSelect } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import { RANGES, rangeWindow, type RangeKey } from "@/features/investigate/index.ts";
import { DEFAULT_KINDS, eventKinds, fetchDensity, fetchEvents, type EventKind } from "./api.ts";
import KindToggles from "./KindToggles.vue";
import DensityStrip from "./DensityStrip.vue";
import EventLog from "./EventLog.vue";
import { densityBucketS, scopeOptions, scopeQuery, scopeValue, timelineScope } from "./model.ts";

/** Timeline (OpsLists §Timeline): fleet-wide events, newest first, with a density strip. */
const mission = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => mission.value.mission.id);

const range = computed<RangeKey>({
  get: () => (route.query.range === "1h" || route.query.range === "6h" ? route.query.range : "24h"),
  set: (r) => {
    router
      .replace({ query: { ...route.query, range: r === "24h" ? undefined : r } })
      .catch((e: unknown) => console.error("Navigation failed", e));
  },
});
const fleet = useFleet(missionId);
const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
/** ?sc= / ?plane= (backlog §2); Investigate's History tab and B2 link pass ?sc=. */
const scope = computed(() => timelineScope(route.query, fleetRows.value));
const scopeModel = computed<string>({
  get: () => scopeValue(scope.value),
  set: (v) => {
    router
      .replace({ query: { ...route.query, ...scopeQuery(v) } })
      .catch((e: unknown) => console.error("Navigation failed", e));
  },
});
const scopeChoices = computed(() => scopeOptions(fleetRows.value, scope.value));
const scopeWords = computed(() =>
  scope.value.kind === "spacecraft"
    ? ` · ${scope.value.name}`
    : scope.value.kind === "plane"
      ? ` · plane ${scope.value.plane}`
      : "",
);
const title = computed(
  () =>
    `Last ${RANGES.find((r) => r.value === range.value)?.label ?? range.value}${scopeWords.value}`,
);
/** Selected kinds from ?kind=limit,command; absent = every kind but `data` (opt-in housekeeping). */
const kinds = computed<EventKind[]>(() => {
  if (typeof route.query.kind !== "string") return [...DEFAULT_KINDS];
  const raw = route.query.kind.split(",");
  return eventKinds.filter((k) => raw.includes(k));
});
function setKinds(next: EventKind[]) {
  const isDefault =
    next.length === DEFAULT_KINDS.length && DEFAULT_KINDS.every((k) => next.includes(k));
  router
    .replace({ query: { ...route.query, kind: isDefault ? undefined : next.join(",") } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
// While ?sc= waits on the fleet read to resolve, don't fetch fleet-wide events by mistake.
const key = computed(() =>
  typeof route.query.sc === "string" && fleet.state.value.status !== "ready"
    ? null
    : JSON.stringify({
        m: missionId.value,
        r: range.value,
        k: kinds.value,
        sc: scope.value.kind === "spacecraft" ? scope.value.id : null,
        p: scope.value.kind === "plane" ? scope.value.plane : null,
      }),
);
type Key = { m: string; r: RangeKey; k: EventKind[]; sc: string | null; p: number | null };
const filters = (k: Key) => ({
  kinds: k.k,
  ...(k.sc ? { spacecraftId: k.sc } : {}),
  ...(k.p !== null ? { plane: k.p } : {}),
});
const windowOf = (r: RangeKey) => {
  const w = rangeWindow(r, new Date());
  return { from: new Date(w.from), to: new Date(w.to) };
};
// Sound: keys are produced by JSON.stringify(Key) above.
const events = useRemoteQuery(key, (k, signal) => {
  const parsed = JSON.parse(k) as Key;
  return fetchEvents(parsed.m, { ...windowOf(parsed.r), ...filters(parsed) }, signal);
});
const density = useRemoteQuery(key, (k, signal) => {
  const parsed = JSON.parse(k) as Key;
  const w = windowOf(parsed.r);
  return fetchDensity(
    parsed.m,
    { ...w, ...filters(parsed) },
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
    <ApPageHeader :label="`${mission.mission.name} · timeline`" :title="title">
      <div class="flex flex-wrap items-end gap-3">
        <ApSelect v-model="scopeModel" :options="scopeChoices" label="Scope" />
        <ApSegmented v-model="range" :options="ranges" label="Window" variant="micro" />
      </div>
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
