<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, plural } from "@/ui";
import StationEditor from "./StationEditor.vue";
import StationsTable from "./StationsTable.vue";
import { fetchStations } from "./api.ts";

/** Setup › Ground stations (rail 06). Edits stage into the change set (ground_station kind). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchStations);
useMissionInvalidation(missionId, ["configuration"], refetch);
const route = useRoute();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
/** `new` = add; an id = edit that station; none = list only. */
const editing = computed(() =>
  typeof route.params.stationId === "string" && route.params.stationId
    ? route.params.stationId
    : null,
);
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
    >
      <ApButton v-if="canStage" :to="{ name: 'setup.stations', params: { stationId: 'new' } }"
        >Add station</ApButton
      >
    </ApPageHeader>
    <template v-if="editing && canStage && state.status === 'ready'">
      <StationEditor
        :key="editing"
        :mission-id="missionId"
        :station="editing === 'new' ? null : (state.value.find((s) => s.id === editing) ?? null)"
      />
    </template>
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
