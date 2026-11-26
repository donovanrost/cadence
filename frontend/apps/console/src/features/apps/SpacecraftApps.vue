<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery, type SpacecraftId } from "@/api";
import { ApEmptyState, ApPanel, ApRemote } from "@/ui";
import AppRow from "./AppRow.vue";
import { fetchScopedApps, SPACECRAFT_APPS_LIVE } from "./api.ts";

/**
 * L19 (api b18dcf7b5): the apps that work per spacecraft (telemetry decom, spacecraft), installed,
 * disabled or removed for this spacecraft alone. Same rows as the mission's Apps.
 */
const props = defineProps<{ missionId: MissionId; spacecraftId: SpacecraftId }>();
const apps = useRemoteQuery(
  () =>
    SPACECRAFT_APPS_LIVE ? { missionId: props.missionId, spacecraftId: props.spacecraftId } : null,
  fetchScopedApps,
);
const notProvided = computed(
  () => apps.state.value.status === "failed" && apps.state.value.error.kind === "not_found",
);
</script>

<template>
  <ApPanel v-if="SPACECRAFT_APPS_LIVE" index="S9" title="Apps" flush>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Spacecraft apps aren't available in the console yet"
    />
    <ApRemote v-else :state="apps.state.value" loading-label="Loading apps…" @retry="apps.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.apps.length === 0"
          state="off"
          headline="No apps work per spacecraft"
        />
        <ul v-else class="m-0 list-none p-0">
          <AppRow
            v-for="a in value.apps"
            :key="a.key"
            :mission-id="missionId"
            :app="a"
            :can-install="value.permissions.includes('apps.install')"
            :uninstall-scope="{ kind: 'spacecraft' }"
            :spacecraft-id="spacecraftId"
            @changed="apps.refetch"
          />
        </ul>
      </template>
    </ApRemote>
  </ApPanel>
</template>
