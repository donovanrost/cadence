<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, plural } from "@/ui";
import { fetchSources } from "./api.ts";
import MissionBindings from "./MissionBindings.vue";
import RegisterSheet from "./RegisterSheet.vue";
import SourcesTable from "./SourcesTable.vue";

/** Setup › Data sources (rail 07): freshness and health as the server judges them (U9). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchSources);
useMissionInvalidation(missionId, ["data_sources"], refetch);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const register = ref<InstanceType<typeof RegisterSheet> | null>(null);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · data sources`"
      :title="
        state.status === 'ready' ? plural(state.value.sources.length, 'source') : 'Data sources'
      "
      size="reading"
    >
      <ApButton
        v-if="state.status === 'ready' && state.value.canManage"
        variant="primary"
        @click="register?.open()"
        >Register source</ApButton
      >
    </ApPageHeader>
    <ApPanel index="D1" title="Sources" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Data sources not available in the console yet"
        sentence="This server doesn't serve data sources to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading data sources…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.sources.length === 0"
            state="off"
            headline="No data sources"
            sentence="Telemetry is stored in the mission's data sources."
          />
          <SourcesTable v-else :sources="value.sources" />
        </template>
      </ApRemote>
    </ApPanel>
    <MissionBindings
      v-if="state.status === 'ready'"
      :mission-id="missionId"
      :sources="state.value.sources"
      :can-manage="state.value.canManage"
    />
    <RegisterSheet ref="register" :mission-id="missionId" />
  </div>
</template>
