<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
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
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
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
          index="F1"
          :title="view === 'table' ? 'Fleet table' : 'Fleet matrix'"
          pane
          flush
          class="console:min-h-0 console:flex-1"
        >
          <ApEmptyState
            v-if="narrowed(value).rows.length === 0"
            :headline="`No spacecraft match ${describeFilter(filter, profileName(value))}`"
          >
            <ApButton size="compact" @click="setFilter(NO_FILTER)">Clear filters</ApButton>
          </ApEmptyState>
          <template v-else-if="view === 'table'">
            <FleetTable
              class="max-md:hidden"
              :rows="narrowed(value).rows"
              :total="value.counts.total"
            />
            <FleetRowList
              class="md:hidden"
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
