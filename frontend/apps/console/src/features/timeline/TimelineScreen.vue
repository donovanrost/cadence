<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import { useHeldNewest } from "./useHeldNewest.ts";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSelect,
  ApSheet,
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
import {
  DEFAULT_KINDS,
  eventKinds,
  fetchDensity,
  fetchEvents,
  fetchEventsPage,
  fetchOlderEvents,
  severityFloors,
  type EventKind,
  type SeverityFloor as Floor,
} from "./api.ts";
import KindToggles from "./KindToggles.vue";
import DensityStrip from "./DensityStrip.vue";
import EventDetail from "./EventDetail.vue";
import EventTypeFilter from "./EventTypeFilter.vue";
import SeverityFloor from "./SeverityFloor.vue";
import EventLog from "./EventLog.vue";
import { useTimelineDetail } from "./useTimelineDetail.ts";
import {
  densityBucketS,
  scopeOptions,
  scopeQuery,
  scopeValue,
  timelineScope,
  withAlertingData,
} from "./model.ts";
import { useOlderEvents } from "./useOlderEvents.ts";

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
/** A typed key (§12 A4; compared by value): no JSON round trip, and the MissionId stays one. */
/** U71 A9b: the Event type filter's choices; EventTypeFilter writes them. */
const rawKinds = computed(() =>
  typeof route.query["raw_kind"] === "string"
    ? route.query["raw_kind"].split(",").filter((s) => s !== "")
    : [],
);
/** U69 A9a: the severity floor (?severity=); SeverityFloor writes it. */
const severity = computed(() => severityFloors.find((f) => f === route.query["severity"]) ?? null);
const filterWindow = computed(() => {
  const r = resolveWindow(sel.value, new Date());
  return { from: new Date(r.from), to: new Date(r.to) };
});
type Key = Readonly<{
  m: MissionId;
  w: WindowSel;
  k: readonly EventKind[];
  sc: string | null;
  p: number | null;
  /** A9b: chosen event types (?raw_kind=). */
  rk: readonly string[];
  sev: Floor | null;
}>;
const key = computed((): Key | null =>
  typeof route.query.sc === "string" && fleet.state.value.status !== "ready"
    ? null
    : {
        m: missionId.value,
        w: sel.value,
        k: kinds.value,
        sc: scope.value.kind === "spacecraft" ? scope.value.id : null,
        p: scope.value.kind === "plane" ? scope.value.plane : null,
        rk: rawKinds.value,
        sev: severity.value,
      },
);
const filters = (k: Key) => ({
  kinds: k.k,
  ...(k.sc ? { spacecraftId: k.sc } : {}),
  ...(k.p !== null ? { plane: k.p } : {}),
  ...(k.rk.length ? { rawKinds: k.rk } : {}),
  ...(k.sev ? { severityAtLeast: k.sev } : {}),
});
const windowOf = (w: WindowSel) => {
  const r = resolveWindow(w, new Date());
  return { from: new Date(r.from), to: new Date(r.to) };
};
const events = useRemoteQuery(key, (k, signal) =>
  fetchEventsPage(k.m, { ...windowOf(k.w), ...filters(k) }, signal),
);
/** A9d: older pages through the first page's cursor; Older events replaces the cap note. */
const older = useOlderEvents(
  key,
  computed(() => (events.state.value.status === "ready" ? events.state.value.value : null)),
  (cursor) => {
    const k = key.value;
    return k
      ? fetchOlderEvents(k.m, { ...windowOf(k.w), ...filters(k) }, cursor)
      : Promise.resolve({
          ok: false,
          error: { kind: "unavailable", status: 0, message: "No window yet." },
        });
  },
);
const density = useRemoteQuery(key, (k, signal) => {
  const w = windowOf(k.w);
  return fetchDensity(
    k.m,
    { ...w, ...filters(k) },
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
  computed(() => (defaultView.value ? key.value : null)),
  (k, signal) => fetchEvents(k.m, { ...windowOf(k.w), ...filters({ ...k, k: ["data"] }) }, signal),
);
/** After Older events, focus the first new row's time (ux U72's Load more rule). */
async function loadOlder() {
  const ids = await older.more();
  await nextTick();
  for (const id of ids) {
    const time = document.querySelector<HTMLElement>(
      `li[data-event-id="${CSS.escape(id)}"] button`,
    );
    if (time) {
      time.focus();
      return;
    }
  }
}
const shownEvents = computed(() => {
  if (events.state.value.status !== "ready") return null;
  const seen = new Set(events.state.value.value.events.map((e) => e.id));
  const main = [
    ...events.state.value.value.events,
    ...older.older.value.filter((e) => !seen.has(e.id)),
  ];
  const d = dataAlerts.state.value;
  return defaultView.value && d.status === "ready" ? withAlertingData(main, d.value.events) : main;
});
const held = useHeldNewest(shownEvents, scroller);
/** Event detail and permalinks (ux U71 A8): useTimelineDetail.ts. */
const detail = ref<InstanceType<typeof EventDetail> | null>(null);
const detailSheet = ref<InstanceType<typeof ApSheet> | null>(null);
const { selection, wide } = useTimelineDetail({
  detail,
  detailSheet,
  missionId,
  shown: shownEvents,
  page: computed(() => (events.state.value.status === "ready" ? events.state.value.value : null)),
  setWindow,
});

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
    <div class="flex flex-none flex-wrap items-center gap-3">
      <KindToggles :selected="kinds" @change="setKinds" />
      <SeverityFloor />
      <EventTypeFilter :mission-id="missionId" :window="filterWindow" :kinds="kinds" />
    </div>
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
      <ApCallout v-if="selection.loadError.value" tone="caution">
        Couldn't load this event: {{ selection.loadError.value }}
        <template #action>
          <ApButton size="compact" variant="secondary" @click="selection.retry">Retry</ApButton>
        </template>
      </ApCallout>
      <ApCallout v-if="selection.notFound.value" tone="info">
        This event isn't in the timeline any more.
        <template #action>
          <ApButton size="compact" variant="secondary" @click="selection.clear">Clear</ApButton>
        </template>
      </ApCallout>
      <div
        class="grid grid-cols-1 gap-2.5 console:min-h-0 console:flex-1"
        :class="selection.event.value && wide ? 'console:grid-cols-[minmax(0,1fr)_380px]' : ''"
      >
        <ApPanel index="E2" title="Event log" pane flush class="console:min-h-0">
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
                <EventLog
                  :events="held.shown.value ?? shownEvents ?? value.events"
                  :selected-id="selection.selectedId.value"
                  @select="selection.toggle"
                />
                <div
                  v-if="older.hasMore.value || older.error.value"
                  class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2"
                >
                  <ApButton
                    size="compact"
                    variant="secondary"
                    :disabled="older.busy.value"
                    disabled-reason="Loading older events…"
                    @click="loadOlder"
                    >Older events</ApButton
                  >
                  <span v-if="older.error.value" class="text-sm text-caution-text" role="status">
                    Couldn't load older events: {{ older.error.value }}
                  </span>
                </div>
              </template>
            </template>
          </ApRemote>
        </ApPanel>
        <aside
          v-if="selection.event.value && wide"
          aria-label="Event detail"
          class="border border-line bg-panel console:min-h-0 console:overflow-auto"
        >
          <EventDetail
            ref="detail"
            :mission-id="missionId"
            :event="selection.event.value"
            @close="selection.clear"
          />
        </aside>
      </div>
      <ApSheet v-if="!wide" ref="detailSheet" title="Event" @closed="selection.clear">
        <EventDetail
          v-if="selection.event.value"
          ref="detail"
          :mission-id="missionId"
          :event="selection.event.value"
          @close="detailSheet?.close()"
        />
      </ApSheet>
    </template>
  </div>
</template>
