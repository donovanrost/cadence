<script setup lang="ts">
import { computed, ref, type ComponentPublicInstance } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope, useSmallScreen } from "@/shell/index.ts";
import { plural, ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented } from "@/ui";
import type { Fleet, FleetSpacecraft } from "./api.ts";
import TelemetryDegraded from "./TelemetryDegraded.vue";
import FleetFilters from "./FleetFilters.vue";
import FleetMatrix from "./FleetMatrix.vue";
import FleetStatStrip from "./FleetStatStrip.vue";
import FleetRowList from "./FleetRowList.vue";
import FleetTable from "./FleetTable.vue";
import {
  byStateThenName,
  describeFilter,
  filterQuery,
  matches,
  NO_FILTER,
  parseFilter,
  type FleetFilter,
} from "./filters.ts";
import { fleetSubset } from "./stats.ts";
import { useFleet } from "./useFleet.ts";
import { useTableBox } from "./useTableBox.ts";

/** Fleet (OpsLists.md §Fleet): the filterable, accessible twin of the Now matrix. */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const fleet = useFleet(computed(() => scope.value.mission.id));

type View = "table" | "matrix";
const view = computed<View>(() => (route.query.view === "matrix" ? "matrix" : "table"));
const views = [
  { value: "table", label: "Table" },
  { value: "matrix", label: "Matrix" },
] as const;
const filter = computed(() => parseFilter(route.query));

/**
 * OpsLists.md › Fleet, option A: with room, the table panel fills to the bottom and is the one
 * vertical scroller (headings and Name stay). With under 360px for it, the screen scrolls
 * instead (option C). Phones get the row list, and the matrix keeps its layout.
 */
const screen = ref<HTMLElement | null>(null);
const panel = ref<ComponentPublicInstance | null>(null);
const small = useSmallScreen();
const tableView = computed(() => view.value === "table" && !small.value);
const boxed = useTableBox(screen, panel, tableView);
const screenClass = computed(() =>
  boxed.value ? "" : tableView.value ? "overflow-auto" : "max-console:overflow-auto",
);
const panelClass = computed(() =>
  boxed.value ? "min-h-0 flex-1" : tableView.value ? "flex-none" : "console:min-h-0 console:flex-1",
);

const go = (query: Parameters<typeof router.replace>[0]) =>
  router.replace(query).catch((error: unknown) => console.error("Navigation failed", error));
const setFilter = (next: FleetFilter) => go({ query: filterQuery(next, route.query) });
const setView = (next: View) =>
  go({ query: { ...route.query, view: next === "table" ? undefined : next } });

const test = (sc: FleetSpacecraft) => matches(sc, filter.value);
function narrowed(value: Fleet) {
  const rows = value.spacecraft.filter(test).sort(byStateThenName);
  return { rows, subset: fleetSubset(value, rows) };
}
const profileName = (value: Fleet) => (id: string) =>
  value.spacecraft.find((sc) => sc.profile?.id === id)?.profile?.name ?? id;
const title = computed(() => {
  const s = fleet.state.value;
  if (s.status !== "ready") return "Fleet";
  const total = s.value.counts.total;
  const shown = s.value.spacecraft.filter(test).length;
  return shown === total
    ? plural(total, "spacecraft", "spacecraft")
    : `${shown} of ${plural(total, "spacecraft", "spacecraft")}`;
});
</script>

<template>
  <div ref="screen" class="flex min-h-0 flex-1 flex-col gap-3" :class="screenClass">
    <ApPageHeader :label="`${scope.mission.name} · fleet`" :title="title">
      <ApSegmented
        :model-value="view"
        :options="views"
        label="View"
        variant="tabs"
        @update:model-value="setView"
      />
    </ApPageHeader>
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <template #default="{ value }">
        <TelemetryDegraded :telemetry="value.telemetry" />
        <FleetFilters :filter="filter" :spacecraft="value.spacecraft" @change="setFilter" />
        <FleetStatStrip :fleet="narrowed(value).subset" />
        <ApPanel
          ref="panel"
          index="F1"
          :title="view === 'table' ? 'Fleet table' : 'Fleet matrix'"
          pane
          flush
          :class="panelClass"
        >
          <ApEmptyState
            v-if="narrowed(value).rows.length === 0"
            :headline="`No spacecraft match ${describeFilter(filter, profileName(value))}`"
          >
            <ApButton size="compact" @click="setFilter(NO_FILTER)">Clear filters</ApButton>
          </ApEmptyState>
          <!-- One list for the viewport, never both: the phone's list renders a link per craft,
            and hidden with CSS on a desktop it still cost Fleet's first render at 1,000. -->
          <template v-else-if="view === 'table'">
            <FleetRowList v-if="small" :rows="narrowed(value).rows" :total="value.counts.total" />
            <FleetTable
              v-else
              :boxed="boxed"
              :rows="narrowed(value).rows"
              :total="value.counts.total"
            />
          </template>
          <div v-else class="p-4">
            <FleetMatrix
              :spacecraft="value.spacecraft"
              :selected-plane="filter.plane"
              :matches="test"
              no-plane-picker
              @open="(sc) => go({ name: 'ops.spacecraft', params: { scId: sc.scid } })"
              @select-plane="(plane) => setFilter({ ...filter, plane })"
            />
          </div>
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
