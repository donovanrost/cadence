<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import {
  plural,
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApGantt,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApTabLinks,
} from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import { passGantt, passStatus, type GanttAxis } from "./gantt.ts";
import SelectedPassPanel from "./SelectedPassPanel.vue";
import { usePasses } from "./usePasses.ts";
import { fetchPass, fetchStations } from "./api.ts";
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
const rangeOptions = RANGES.map((r) => ({ value: r.value, label: r.label }));
const stationsQuery = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
useMissionInvalidation(missionId, ["configuration"], stationsQuery.refetch);
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
const list = computed(() =>
  passes.state.value.status === "ready" ? passes.state.value.value.passes : [],
);
/** A pass named in the URL but outside the window (Review from Now, U31) is read on its own. */
const outsideKey = computed(() => {
  const id = selectedId.value;
  if (id === null || passes.state.value.status !== "ready") return null;
  return list.value.some((p) => p.id === id) ? null : `${missionId.value}|${id}`;
});
const outside = useRemoteQuery(outsideKey, (k, signal) => {
  const [m = "", id = ""] = k.split("|");
  return fetchPass(m, id, signal);
});
useMissionInvalidation(missionId, ["contacts", "attention"], outside.refetch);
const outsidePass = computed(() =>
  outside.state.value.status === "ready" ? outside.state.value.value : null,
);
function refetchPass() {
  passes.refetch();
  if (outsideKey.value !== null) outside.refetch();
}
/** Default selection: the pass named in the URL, else the next AOS fleet-wide. */
const selected = computed(() => {
  const t = now.value.getTime();
  return (
    list.value.find((p) => p.id === selectedId.value) ??
    outsidePass.value ??
    list.value.find((p) => Date.parse(p.starts_at) > t && passStatus(p, t) === "scheduled") ??
    null
  );
});
/** D2 identity: the fleet row (has state) else the pass's own {name, scid}. */
const selectedSpacecraft = computed(() => {
  const p = selected.value;
  if (!p) return null;
  const known = p.spacecraft_id ? byId.value.get(p.spacecraft_id) : undefined;
  if (known) return known;
  return p.spacecraft?.scid != null ? { name: p.spacecraft.name, scid: p.spacecraft.scid } : null;
});
const view = computed(() => {
  const s = passes.state.value;
  // Wait for the fleet too: rows and D2 are labelled by name (R01), never by raw id.
  if (s.status !== "ready" || fleet.state.value.status !== "ready") return null;
  const window = { from: Date.parse(s.value.from), to: Date.parse(s.value.to) };
  return {
    window,
    ...passGantt(
      s.value.passes,
      (id) => byId.value.get(id) ?? null,
      now.value.getTime(),
      selected.value?.id ?? null,
      axis.value,
    ),
  };
});
const meta = computed(() => {
  const t = now.value.getTime();
  const live = list.value.filter((p) => passStatus(p, t) === "live").length;
  const ahead = list.value.filter(
    (p) => Date.parse(p.starts_at) > t && passStatus(p, t) !== "canceled",
  ).length;
  return `${plural(ahead, "pass", "passes")} next ${range.value.label.toLowerCase()} · ${live} AOS now`;
});
const tabs = [
  { key: "live", label: "Live", to: { name: "ops.contacts" } },
  { key: "plan", label: "Plan", to: { name: "ops.contacts.plan" } },
  { key: "review", label: "Review", to: { name: "ops.contacts.review" } },
];
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
      <p class="m-0 font-mono text-sm text-text-3 uppercase">{{ meta }}</p>
    </ApPageHeader>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <ApTabLinks :links="tabs" active="live" label="Contacts sections" />
      <div class="flex gap-3">
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
      <ApPanel index="D1" title="Ground track" flush class="flex-none">
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
          :title="`Pass schedule · ${range.label.toLowerCase()}`"
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
              headline="No passes in the next 6 h"
            />
            <div v-else-if="view" class="p-3">
              <ApGantt
                label="Pass schedule for the next six hours"
                :rows="view.rows"
                :bars="view.bars"
                :window="view.window"
                :now="now.getTime()"
                :selected="selected?.id ?? null"
                @select="(id) => go({ contact: id })"
              />
            </div>
          </ApRemote>
        </ApPanel>
        <SelectedPassPanel
          :mission-id="missionId"
          :pass="selected"
          :spacecraft="selectedSpacecraft"
          @changed="refetchPass"
        />
      </div>
    </template>
  </div>
</template>
