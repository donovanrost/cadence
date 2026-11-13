<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote } from "@/ui";
import AppRow from "./AppRow.vue";
import { fetchApps } from "./api.ts";

/** Setup › Apps (rail 08): what's installed and what's off because an app is missing. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchApps);
useMissionInvalidation(missionId, ["configuration"], refetch);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const installedCount = computed(() =>
  state.value.status === "ready" ? state.value.value.apps.filter((a) => a.installed).length : null,
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · apps`"
      :title="
        state.status === 'ready'
          ? `${installedCount} of ${state.value.apps.length} installed`
          : 'Apps'
      "
      size="reading"
    />
    <ApPanel index="A1" title="Apps" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Apps not available in the console yet"
        sentence="This server doesn't serve the app inventory to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading apps…" @retry="refetch">
        <template #default="{ value }">
          <ul class="m-0 list-none p-0">
            <AppRow
              v-for="a in value.apps"
              :key="a.key"
              :mission-id="missionId"
              :app="a"
              :can-install="value.permissions.includes('apps.install')"
              @changed="refetch"
            />
          </ul>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
