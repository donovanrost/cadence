<script setup lang="ts">
import { computed, ref } from "vue";
import { useHeldNewest } from "./useHeldNewest.ts";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  useNow,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSelect,
  ApTimeRange,
  type TimeRange,
} from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import {
  parseWindow,
  resolveWindow,
  windowFromRange,
  windowLabel,
  windowPresets,
  windowQuery,
  type WindowSel,
} from "@/features/telemetry/index.ts";
import { DEFAULT_KINDS, eventKinds, fetchDensity, fetchEvents, type EventKind } from "./api.ts";
import KindToggles from "./KindToggles.vue";
import DensityStrip from "./DensityStrip.vue";
import EventLog from "./EventLog.vue";
import {
  densityBucketS,
  scopeOptions,
  scopeQuery,
  scopeValue,
  timelineScope,
  withAlertingData,
} from "./model.ts";

/** Timeline (OpsLists §Timeline): fleet-wide events, newest first, with a density strip. */
const mission = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => mission.value.mission.id);

/**
 * The window: a preset sliding with now (`?range=6h`, default 24 h) or a fixed custom range
 * (`?from=…&to=…`), from the picker or an E1 brush (OpsLists §Timeline). Keys use the selection,
 * not the resolved times, so a preset doesn't refetch every tick.
 */
const sel = computed<WindowSel>(() => parseWindow(route.query, "24h"));
function setWindow(next: WindowSel) {
  router
    .replace({ query: windowQuery(next, route.query, "24h") })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
/** The picker's value; `new Date()` unreactive on purpose (it changes only on the user's pick). */
const pickerWindow = computed<TimeRange>({
  get: () => resolveWindow(sel.value, new Date()),
  set: (r) => setWindow(windowFromRange(r, new Date())),
});
const presets = windowPresets(new Date());
/** E1 brush: drag across the strip to narrow the window to that span. */
const brushTo = (r: TimeRange) => setWindow({ kind: "custom", from: r.from, to: r.to });
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
const title = computed(() => `${windowLabel(sel.value)}${scopeWords.value}`);
/**
 * Selected kinds from ?kind=limit,command. Absent = every kind but `data` (housekeeping), plus any
 * caution/critical data event (ux): failures show by default, routine noise doesn't.
 */
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
        w: sel.value,
        k: kinds.value,
        sc: scope.value.kind === "spacecraft" ? scope.value.id : null,
        p: scope.value.kind === "plane" ? scope.value.plane : null,
      }),
);
type Key = { m: string; w: WindowSel; k: EventKind[]; sc: string | null; p: number | null };
const filters = (k: Key) => ({
  kinds: k.k,
  ...(k.sc ? { spacecraftId: k.sc } : {}),
  ...(k.p !== null ? { plane: k.p } : {}),
});
const windowOf = (w: WindowSel) => {
  const r = resolveWindow(w, new Date());
  return { from: new Date(r.from), to: new Date(r.to) };
};
// Sound: keys are produced by JSON.stringify(Key) above.
const events = useRemoteQuery(key, (k, signal) => {
  const parsed = JSON.parse(k) as Key;
  return fetchEvents(parsed.m, { ...windowOf(parsed.w), ...filters(parsed) }, signal);
});
const density = useRemoteQuery(key, (k, signal) => {
  const parsed = JSON.parse(k) as Key;
  const w = windowOf(parsed.w);
  return fetchDensity(
    parsed.m,
    { ...w, ...filters(parsed) },
    densityBucketS(w.to.getTime() - w.from.getTime()),
    signal,
  );
});
useMissionInvalidation(
  missionId,
  ["events", "alarms"],
  () => {
    events.refetch();
    density.refetch();
    if (defaultView.value) dataAlerts.refetch();
  },
  { throttleMs: 2000 },
);
/** Live prepend: hold new events while the reader is scrolled away (lead 79ec6dc6). */
const logAnchor = ref<HTMLElement | null>(null);
const scroller = computed(() => {
  let el = logAnchor.value?.parentElement ?? null;
  while (el && !/(auto|scroll)/.test(getComputedStyle(el).overflowY)) el = el.parentElement;
  return el;
});
/** Default view only: the data kind's caution/critical events, merged in (ux). */
const defaultView = computed(() => typeof route.query.kind !== "string");
const dataAlerts = useRemoteQuery(
  computed(() => (defaultView.value && key.value ? `${key.value}|data` : null)),
  (k, signal) => {
    const parsed = JSON.parse(k.slice(0, -5)) as Key;
    return fetchEvents(
      parsed.m,
      { ...windowOf(parsed.w), ...filters({ ...parsed, k: ["data"] }) },
      signal,
    );
  },
);
const shownEvents = computed(() => {
  if (events.state.value.status !== "ready") return null;
  const main = events.state.value.value.events;
  const d = dataAlerts.state.value;
  return defaultView.value && d.status === "ready" ? withAlertingData(main, d.value.events) : main;
});
const held = useHeldNewest(shownEvents, scroller);

const missing = computed(
  () => events.state.value.status === "failed" && events.state.value.error.kind === "not_found",
);
/** OpsLists §Timeline empty range: "No events between 02:00Z and 03:00Z." */
const short = (iso: string) => {
  const today = iso.slice(0, 10) === new Date().toISOString().slice(0, 10);
  return `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
};
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${mission.mission.name} · timeline`" :title="title">
      <div class="flex flex-wrap items-end gap-3">
        <ApSelect v-model="scopeModel" :options="scopeChoices" label="Scope" />
        <ApTimeRange v-model="pickerWindow" label="Window" :presets="presets" />
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
          @brush="brushTo"
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
              v-if="(shownEvents ?? value.events).length === 0"
              :headline="`No events between ${short(value.from)} and ${short(value.to)}.`"
            />
            <template v-else>
              <div ref="logAnchor" aria-hidden="true" />
              <button
                v-if="held.pending.value > 0"
                type="button"
                class="sticky top-0 z-10 w-full cursor-pointer border-b border-hairline bg-raised px-4 py-2 text-left font-mono text-xs text-readout uppercase hover:text-bright"
                @click="held.showNew"
              >
                {{ held.pending.value }} new {{ held.pending.value === 1 ? "event" : "events" }} ↑
              </button>
              <EventLog :events="held.shown.value ?? shownEvents ?? value.events" />
            </template>
          </template>
        </ApRemote>
      </ApPanel>
    </template>
  </div>
</template>
