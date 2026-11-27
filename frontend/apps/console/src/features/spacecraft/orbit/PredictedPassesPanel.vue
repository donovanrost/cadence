<script setup lang="ts">
import { computed, shallowRef } from "vue";
import { RouterLink } from "vue-router";
import { usePagedQuery, type MissionId, type SpacecraftId } from "@/api";
import { useMissionInvalidation } from "@/live";
import { ApCallout, ApEmptyState, ApPanel, ApRemote, ApTable, type ApColumn } from "@/ui";
import OrbitPagedFooter from "./OrbitPagedFooter.vue";
import { fetchPredictedPassPage, passesKey } from "./api.ts";
import { coverageLines, elevation, horizonWords, passTime, stationLine } from "./words.ts";

/**
 * D8 Predicted passes (#895): the spacecraft's passes over every station, AOS first, from now to
 * the server's horizon (geometry, not bookings). The meta names the horizon; the coverage every page
 * carries says why the list is empty or short.
 */
const props = defineProps<{ missionId: MissionId; spacecraftId: SpacecraftId }>();
/** The window's start. A live change moves it to now, so passes that ended drop off. */
const from = shallowRef(new Date());
const key = computed(() =>
  passesKey({ missionId: props.missionId, spacecraftId: props.spacecraftId }, from.value),
);
// A moved window is a filter change: the passes shown stay until the new first page lands.
const passes = usePagedQuery(key, fetchPredictedPassPage, (p) => p.id, {
  scopeOf: (k) => [k.missionId, k.spacecraftId],
});
useMissionInvalidation(
  computed(() => props.missionId),
  ["predicted_passes", "stations"],
  () => (from.value = new Date()),
);
const columns: readonly ApColumn[] = [
  { key: "station", label: "Station" },
  { key: "aos", label: "AOS", mono: true },
  { key: "tca", label: "TCA", mono: true },
  { key: "los", label: "LOS", mono: true },
  { key: "elevation", label: "Max elevation", mono: true, align: "end" },
];
const coverage = computed(() =>
  passes.state.value.status === "ready" ? passes.state.value.value.meta : null,
);
const horizon = computed(() => (coverage.value ? horizonWords(coverage.value) : null));
const lines = computed(() => (coverage.value ? coverageLines(coverage.value) : []));
</script>

<template>
  <ApPanel index="D8" title="Predicted passes" flush>
    <template #meta>
      <span v-if="horizon">Predicted to {{ horizon }}</span>
      <span role="status">{{ passes.pending.value ? " · Updating…" : "" }}</span>
    </template>
    <ApRemote
      :state="passes.state.value"
      loading-label="Loading predicted passes…"
      @retry="passes.refetch"
    >
      <template #default="{ value: page }">
        <div class="flex flex-col">
          <div v-if="lines.length > 0" class="flex flex-col gap-2 px-4 py-3">
            <ApCallout v-for="line in lines" :key="line.key" :tone="line.tone">{{
              line.text
            }}</ApCallout>
          </div>
          <ApEmptyState
            v-if="page.items.length === 0"
            state="off"
            :headline="horizon ? `No predicted passes before ${horizon}` : 'No predicted passes'"
          />
          <ApTable
            v-else
            :columns="columns"
            :rows="page.items"
            :row-key="(p) => p.id"
            caption="Predicted passes, AOS first"
          >
            <template #cell-station="{ row }">
              <RouterLink
                :to="{ name: 'setup.stations', params: { stationId: row.station.id } }"
                class="text-readout hover:text-bright max-md:hit-44"
                >{{ stationLine(row) }}</RouterLink
              >
            </template>
            <template #cell-aos="{ row }">{{ passTime(row.aos) }}</template>
            <template #cell-tca="{ row }">{{ passTime(row.tca) }}</template>
            <template #cell-los="{ row }">{{ passTime(row.los) }}</template>
            <template #cell-elevation="{ row }">{{ elevation(row.max_elevation_deg) }}</template>
            <template #footer>
              <OrbitPagedFooter
                :shown="page.items.length"
                :has-more="page.next !== null"
                :loading="passes.moreBusy.value || passes.pending.value"
                :error="passes.moreError.value"
                no-more="No later predicted passes"
                @more="passes.more"
              />
            </template>
          </ApTable>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
