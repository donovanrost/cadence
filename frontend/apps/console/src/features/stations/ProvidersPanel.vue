<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { paramText } from "@/shell";
import { ApButton, ApEmptyState, ApPanel, ApRemote } from "@/ui";
import { fetchProviders } from "./api.ts";
import ProviderAddSheet from "./ProviderAddSheet.vue";
import ProviderDetail from "./ProviderDetail.vue";
import ProvidersTable from "./ProvidersTable.vue";

/** Stations · Providers (ux U4): the ground networks that supply this mission's stations (L12). */
const props = defineProps<{ missionId: MissionId }>();
const route = useRoute();
const providerId = computed(() => paramText(route.params, "providerId") || null);
const { state, refetch } = useRemoteQuery(() => props.missionId, fetchProviders);
// setup.md (#972): providers after an upload run, a write, validate or sync; stations for counts.
useMissionInvalidation(
  computed(() => props.missionId),
  ["providers", "stations"],
  refetch,
);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const add = ref<InstanceType<typeof ProviderAddSheet> | null>(null);
</script>

<template>
  <ApPanel index="G3" title="Providers" flush>
    <template v-if="state.status === 'ready' && state.value.canManage && !providerId" #header>
      <ApButton size="compact" variant="primary" @click="add?.open()">Add provider</ApButton>
    </template>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Providers aren't available in the console yet"
    />
    <ApRemote v-else :state="state" loading-label="Loading providers…" @retry="refetch">
      <template #default="{ value }">
        <ProviderDetail
          v-if="providerId"
          :mission-id="missionId"
          :provider="value.providers.find((p) => p.id === providerId) ?? null"
          :can-manage="value.canManage"
          @changed="refetch"
        />
        <ApEmptyState
          v-else-if="value.providers.length === 0"
          state="off"
          headline="No ground-network providers"
          sentence="Providers supply stations, antennas and pass opportunities."
        />
        <ProvidersTable v-else :providers="value.providers" />
        <p v-if="!value.canManage" class="m-0 px-4 py-3 text-sm text-text-3">
          Mission admins change providers.
        </p>
      </template>
    </ApRemote>
    <ProviderAddSheet ref="add" :mission-id="missionId" @added="refetch" />
  </ApPanel>
</template>
