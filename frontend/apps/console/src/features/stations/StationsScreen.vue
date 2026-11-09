<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, plural } from "@/ui";
import StationsTable from "./StationsTable.vue";
import { fetchStations } from "./api.ts";

/** Setup › Ground stations (rail 06). Edits stage into the change set (ground_station kind). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchStations);
useMissionInvalidation(missionId, ["configuration"], refetch);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · ground stations`"
      :title="
        state.status === 'ready'
          ? plural(state.value.filter((s) => s.lifecycle_state === 'active').length, 'station')
          : 'Ground stations'
      "
      size="reading"
    />
    <ApPanel index="G1" title="Stations" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Stations not available in the console yet"
        sentence="This server doesn't serve ground stations to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading stations…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.length === 0"
            state="off"
            headline="No ground stations yet"
            sentence="Stations come from your ground-network providers or are added here."
          />
          <StationsTable v-else :rows="value" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
