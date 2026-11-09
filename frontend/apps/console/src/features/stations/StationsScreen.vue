<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks, plural } from "@/ui";
import ProvidersPanel from "./ProvidersPanel.vue";
import { KindEditor } from "@/features/changes/index.ts";
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
const tab = computed(() => (route.name === "setup.stations.providers" ? "providers" : "stations"));
const tabs = [
  { key: "stations", label: "Stations", to: { name: "setup.stations" } },
  { key: "providers", label: "Providers", to: { name: "setup.stations.providers" } },
];
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
    <ApTabLinks :links="tabs" :active="tab" label="Ground station sections" />
    <ProvidersPanel v-if="tab === 'providers'" :mission-id="missionId" />
    <template v-if="tab === 'stations' && editing && canStage && state.status === 'ready'">
      <KindEditor
        :key="editing"
        :mission-id="missionId"
        kind="ground_station"
        :entity-id="editing === 'new' ? null : editing"
        :document="editing === 'new' ? {} : (state.value.find((s) => s.id === editing) ?? {})"
        :name="
          editing === 'new'
            ? 'station'
            : (state.value.find((s) => s.id === editing)?.display_name ?? 'station')
        "
        index="G2"
        surface="stations"
        :done="{ name: 'setup.stations' }"
      />
    </template>
    <ApPanel v-if="tab === 'stations'" index="G1" title="Stations" flush>
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
          <StationsTable v-else :rows="value" :can-edit="canStage" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
