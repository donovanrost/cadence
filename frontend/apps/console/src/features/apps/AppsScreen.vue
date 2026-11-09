<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApListRow, ApPageHeader, ApPanel, ApRemote, ApTag } from "@/ui";
import AppActions from "./AppActions.vue";
import { fetchApps, type App } from "./api.ts";

/** Setup › Apps (rail 08): what's installed and what's off because an app is missing. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchApps);
useMissionInvalidation(missionId, ["settings"], refetch);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const installedCount = computed(() =>
  state.value.status === "ready" ? state.value.value.apps.filter((a) => a.installed).length : null,
);
const word = (a: App) =>
  a.state === "installed" ? "Installed" : a.state === "disabled" ? "Disabled" : "Not set up";
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
            <ApListRow
              v-for="a in value.apps"
              :key="a.key"
              :state="a.state === 'installed' ? 'nominal' : 'off'"
              :title="a.name"
              :sentence="
                a.installed
                  ? (a.description ?? undefined)
                  : (a.consequence_if_missing ?? a.description ?? undefined)
              "
              :meta="a.version ? `v${a.version}` : undefined"
            >
              <template #action>
                <div class="flex flex-col items-end gap-2">
                  <ApTag :state="a.state === 'installed' ? 'nominal' : 'off'" :label="word(a)" />
                  <AppActions
                    v-if="value.permissions.includes('apps.install')"
                    :mission-id="missionId"
                    :app="a"
                    @changed="refetch"
                  />
                </div>
              </template>
            </ApListRow>
          </ul>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
