<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import {
  plural,
  useNow,
  ApButton,
  ApCallout,
  ApChip,
  ApField,
  ApEmptyState,
  ApGantt,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApTabLinks,
} from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import { fetchGroups } from "@/features/commands/index.ts";
import { availabilityBands, passGantt, passStatus, type GanttAxis } from "./gantt.ts";
import { fetchAvailability } from "@/features/scheduling/index.ts";
import SelectedPassPanel from "./SelectedPassPanel.vue";
import BookPassSheet from "./BookPassSheet.vue";
import { SINGLE_BOOKINGS_LIVE } from "./singleBookings.ts";
import { useCommandAccess } from "@/features/commands/index.ts";
import FindingsPanel from "./FindingsPanel.vue";
import { findingsMeta, useFindings } from "./findings.ts";
import { usePasses } from "./usePasses.ts";
import { fetchStations, type Pass } from "./api.ts";
import { contactsSections } from "./sections.ts";
import { useSelectedPass } from "./useSelectedPass.ts";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";

/**
 * J4 · Contacts, Live (Contacts.md): 6 h pass schedule by station or spacecraft, the selected pass,
 * and an honest collapsed ground-track strip (DECISIONS #4). D4 hides until conflict findings (M22).
 */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
const RANGES = [
  { value: "2h", label: "2H", ms: 2 * 3_600_000 },
  { value: "6h", label: "6H", ms: 6 * 3_600_000 },
] as const;
const range = computed(() => (route.query.range === "2h" ? RANGES[0] : RANGES[1]));
const passes = usePasses(
  missionId,
  30 * 60_000,
  computed(() => range.value.ms),
);
/** §4: "6 h", not "6h" (ux §7 #17). */
const rangeWords = computed(() => range.value.label.toLowerCase().replace(/h$/, " h"));
const rangeOptions = RANGES.map((r) => ({ value: r.value, label: r.label }));
/** D4 (M22): hidden when the read isn't available (Contacts.md: "Unavailable: hide D4"). */
const findings = useFindings(
  missionId,
  computed(() => range.value.ms),
);
const findingsReady = computed(() =>
  findings.state.value.status === "ready" ? findings.state.value.value : null,
);
const stationsQuery = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
useMissionInvalidation(missionId, ["configuration"], stationsQuery.refetch);
/** S7 station availability → outage / maintenance / degraded bands on the station rows (D3). */
const availability = useRemoteQuery(missionId, (id, signal) => fetchAvailability(id, signal));
useMissionInvalidation(missionId, ["stations"], availability.refetch);
const bands = computed(() => {
  const v = view.value;
  const a = availability.state.value;
  return v && axis.value === "station"
    ? availabilityBands(a.status === "ready" ? a.value : null, v.rows, v.window.to)
    : [];
});
/** null = unknown (not loaded or failed): the label omits the count rather than guess. */
const stationCount = computed(() =>
  stationsQuery.state.value.status === "ready"
    ? stationsQuery.state.value.value.stations.length
    : null,
);

const go = (query: Record<string, string | undefined>) =>
  router
    .replace({ query: { ...route.query, ...query } })
    .catch((e: unknown) => console.error("Navigation failed", e));
const axis = computed<GanttAxis>(() =>
  route.query.view === "spacecraft" ? "spacecraft" : "station",
);
const axes = [
  { value: "station", label: "By station" },
  { value: "spacecraft", label: "By spacecraft" },
] as const;
const selectedId = computed(() =>
  typeof route.query.contact === "string" ? route.query.contact : null,
);

const byId = computed(() => {
  const s = fleet.state.value;
  return new Map((s.status === "ready" ? s.value.spacecraft : []).map((sc) => [sc.id, sc]));
});
const all = computed(() =>
  passes.state.value.status === "ready" ? passes.state.value.value.passes : [],
);
/** Palette `@` (Palette.md): `?station=<id>` narrows the schedule to that station's passes. */
const stationId = computed(() =>
  typeof route.query.station === "string" ? route.query.station : null,
);
const atStation = (p: Pass) =>
  stationId.value === null || p.station.id === stationId.value || p.station.ref === stationId.value;
const list = computed(() => all.value.filter(atStation));
/**
 * D3 chips (Contacts.md): `sc any` (?sc=, name or SCID) highlights that spacecraft's passes in
 * place and dims the rest; `highlight queued uplinks` (?uplinks=1) notches bars with requests
 * queued on them (a group's U33 uplink.pass).
 */
const scText = computed({
  get: () => (typeof route.query.sc === "string" ? route.query.sc : ""),
  set: (v: string) => go({ sc: v.trim() || undefined }),
});
const scMatch = computed(() => {
  const q = scText.value.toLowerCase();
  if (!q) return null;
  return (p: Pass) => {
    const sc = (p.spacecraft_id ? byId.value.get(p.spacecraft_id) : undefined) ?? p.spacecraft;
    return (
      !!sc &&
      ((sc.name ?? "").toLowerCase().includes(q) ||
        (sc.scid != null && String(sc.scid).startsWith(q)))
    );
  };
});
const showUplinks = computed(() => route.query.uplinks === "1");
const queuedGroups = useRemoteQuery(
  computed(() => (showUplinks.value ? missionId.value : null)),
  (m, signal) => fetchGroups(m, { states: ["queued", "approval_pending"] }, signal),
);
useMissionInvalidation(missionId, ["commanding"], queuedGroups.refetch);
const uplinkPasses = computed<ReadonlySet<string>>(() => {
  const g = queuedGroups.state.value;
  return new Set(
    g.status === "ready" && showUplinks.value
      ? g.value.flatMap((row) =>
          row.finished !== true && row.uplink?.pass ? [row.uplink.pass.reservation_id] : [],
        )
      : [],
  );
});
const stationName = computed(() => {
  const id = stationId.value;
  const s = stationsQuery.state.value;
  const known = s.status === "ready" ? s.value.stations.find((x) => x.id === id) : undefined;
  const pass = all.value.find((p) => p.station.id === id);
  return known?.display_name ?? known?.code ?? pass?.station.name ?? id ?? "";
});
const pick = useSelectedPass(missionId, passes, list, selectedId, byId, now);
const { selected, loading: selectedLoading, missing: selectedMissing } = pick;
const view = computed(() => {
  const s = passes.state.value;
  // Wait for the fleet too: rows and D2 are labelled by name (R01), never by raw id.
  if (s.status !== "ready" || fleet.state.value.status !== "ready") return null;
  const window = { from: Date.parse(s.value.from), to: Date.parse(s.value.to) };
  return {
    window,
    ...passGantt(
      s.value.passes.filter(atStation),
      (id) => byId.value.get(id) ?? null,
      now.value.getTime(),
      selected.value?.id ?? null,
      axis.value,
      { match: scMatch.value, uplinks: uplinkPasses.value },
    ),
  };
});
const meta = computed(() => {
  const t = now.value.getTime();
  const live = list.value.filter((p) => passStatus(p, t) === "live").length;
  const ahead = list.value.filter(
    (p) => Date.parse(p.starts_at) > t && passStatus(p, t) !== "canceled",
  ).length;
  const issues = findingsMeta(findingsReady.value);
  return `${plural(ahead, "pass", "passes")} next ${rangeWords.value} · ${live} AOS now${issues ? ` · ${issues}` : ""}`;
});
/**
 * Book a pass (§11 L15, ux Contacts.md): header entry (operate_mission), D4 gap rows prefilled, and
 * `?book=<spacecraft id>[&book_from&book_to]` from Investigate › Passes and Planning › requirement.
 * Off until the single-booking endpoints exist.
 */
const access = useCommandAccess();
const bookSheet = ref<InstanceType<typeof BookPassSheet> | null>(null);
function openBook(prefill: { spacecraftId?: string; from?: number; to?: number } = {}) {
  bookSheet.value?.open(prefill);
}
watch(
  () => route.query.book,
  (b) => {
    if (!SINGLE_BOOKINGS_LIVE || typeof b !== "string") return;
    // fe-ops: the window rides only with book; a bad or reversed one opens with the spacecraft alone.
    const at = (v: unknown) => (typeof v === "string" ? Date.parse(v) : Number.NaN);
    const from = at(route.query.book_from);
    const to = at(route.query.book_to);
    const range = Number.isFinite(from) && Number.isFinite(to) && from < to ? { from, to } : {};
    void nextTick(() => openBook({ spacecraftId: b, ...range }));
    go({ book: undefined, book_from: undefined, book_to: undefined });
  },
  { immediate: true },
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader
      :label="
        stationCount === null
          ? 'Ground network'
          : `Ground network · ${plural(stationCount, 'station')}`
      "
      title="Contacts"
    >
      <div class="flex flex-wrap items-center gap-3">
        <p class="m-0 font-mono text-sm text-text-3 uppercase">{{ meta }}</p>
        <!-- Contacts.md: Book passes is a shortcut to Plan (single bookings come with L15). -->
        <ApButton size="compact" :to="{ name: 'ops.contacts.plan' }">Book passes</ApButton>
        <ApButton
          v-if="SINGLE_BOOKINGS_LIVE && access.abort"
          size="compact"
          variant="secondary"
          @click="openBook()"
          >Book a pass</ApButton
        >
      </div>
    </ApPageHeader>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <ApTabLinks :links="contactsSections" active="live" label="Contacts sections" />
      <div class="flex flex-wrap items-center gap-3">
        <div class="w-40">
          <ApField
            v-model="scText"
            label="Spacecraft"
            hidden-label
            type="search"
            mono
            placeholder="sc any"
          />
        </div>
        <button
          type="button"
          class="inline-flex h-11 cursor-pointer items-center border px-3 font-display text-md font-semibold tracking-tag uppercase"
          :class="
            showUplinks
              ? 'border-readout bg-raised text-readout'
              : 'border-line text-text-3 hover:text-readout'
          "
          :aria-pressed="showUplinks"
          @click="go({ uplinks: showUplinks ? undefined : '1' })"
        >
          Highlight queued uplinks
        </button>
        <ApChip
          v-if="stationId !== null"
          name="STATION"
          removable
          remove-label="Show all stations"
          @remove="go({ station: undefined })"
          >{{ stationName }}</ApChip
        >
        <ApSegmented
          :model-value="range.value"
          :options="rangeOptions"
          label="Window"
          variant="micro"
          @update:model-value="(v) => go({ range: v === '6h' ? undefined : v })"
        />
        <ApSegmented
          :model-value="axis"
          :options="axes"
          label="Rows"
          @update:model-value="(v) => go({ view: v === 'station' ? undefined : v })"
        />
      </div>
    </div>
    <ApPanel v-if="stationCount === 0" index="D3" title="Pass schedule" flush>
      <ApEmptyState
        headline="No ground stations yet"
        sentence="Add a station before booking passes."
      >
        <ApButton size="compact" :to="{ name: 'setup.stations' }">Add a station</ApButton>
      </ApEmptyState>
    </ApPanel>
    <template v-else>
      <ApCallout v-if="list.some((p) => p.source.synthetic)" tone="stale">
        These passes are the simulator's synthetic windows, not a real ground provider's.
      </ApCallout>
      <!-- ux §7 #17: on a phone, D1 hides while it's unavailable and D2 until a bar is chosen, so
           D4 is on the first screen. -->
      <ApPanel index="D1" title="Ground track" flush class="flex-none max-md:hidden">
        <ApEmptyState
          state="off"
          headline="Ground track not available"
          sentence="Station locations and orbit propagation aren't in Cadence yet. The schedule below is live."
        />
      </ApPanel>
      <div
        class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_360px]"
      >
        <ApPanel
          index="D3"
          :title="`Pass schedule · ${rangeWords}`"
          :meta="view ? `${view.bars.length} in view` : undefined"
          pane
          flush
        >
          <ApRemote
            :state="passes.state.value"
            loading-label="LOADING PASSES…"
            @retry="passes.refetch"
          >
            <ApEmptyState
              v-if="view && view.bars.length === 0"
              :headline="`No passes${stationId === null ? '' : ` at ${stationName}`} in the next ${rangeWords}`"
            />
            <div v-else-if="view" class="p-3">
              <ApGantt
                label="Pass schedule for the next six hours"
                :rows="view.rows"
                :bars="view.bars"
                :bands="bands"
                :window="view.window"
                :now="now.getTime()"
                :selected="selected?.id ?? null"
                @select="(id) => go({ contact: id })"
              />
            </div>
          </ApRemote>
        </ApPanel>
        <div class="flex min-h-0 flex-col gap-3">
          <SelectedPassPanel
            :class="selectedId === null ? 'max-md:hidden' : undefined"
            :mission-id="missionId"
            :pass="selected"
            :loading="selectedLoading"
            :missing="selectedMissing"
            :spacecraft="pick.spacecraft.value"
            @changed="pick.refetch"
          />
          <FindingsPanel
            v-if="findingsReady"
            :findings="findingsReady"
            :label="rangeWords"
            :can-book="SINGLE_BOOKINGS_LIVE && access.abort"
            @book="openBook"
          />
        </div>
      </div>
    </template>
    <BookPassSheet
      ref="bookSheet"
      :mission-id="missionId"
      :fleet="[...byId.values()]"
      @booked="(p) => go({ contact: p.id })"
    />
  </div>
</template>
