<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, ApTable, formatShort, type ApColumn } from "@/ui";
import { fetchProviders } from "./api.ts";

/** Stations · Providers (ux U4): the ground networks that supply this mission's stations. */
const props = defineProps<{ missionId: string }>();
const { state, refetch } = useRemoteQuery(() => props.missionId, fetchProviders);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Provider" },
  { key: "account", label: "Account" },
  { key: "stations", label: "Stations", mono: true, align: "end" },
  { key: "validated", label: "Last validated", mono: true },
  { key: "synced", label: "Last synced", mono: true },
];
const when = (at: string | null) => (at ? formatShort(new Date(at)) : "never");
</script>

<template>
  <ApPanel index="G3" title="Providers" flush>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Providers aren't available in the console yet"
    />
    <ApRemote v-else :state="state" loading-label="Loading providers…" @retry="refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.length === 0"
          state="off"
          headline="No ground-network providers"
          sentence="Providers supply stations, antennas and pass opportunities."
        />
        <ApTable v-else :columns="columns" :rows="value" :row-key="(p) => p.id" caption="Providers">
          <template #cell-name="{ row }">
            <span class="font-semibold text-readout">{{ row.name }}</span>
            <span class="font-mono text-xs text-text-4"> {{ row.provider_type }}</span>
            <span v-if="row.status.lifecycle_state !== 'active'" class="text-xs text-text-4">
              · {{ row.status.lifecycle_state }}</span
            >
          </template>
          <template #cell-account="{ row }">{{ row.account.name ?? "Org admins only" }}</template>
          <template #cell-stations="{ row }">{{ row.station_count }}</template>
          <template #cell-validated="{ row }">{{ when(row.status.last_validated_at) }}</template>
          <template #cell-synced="{ row }">{{ when(row.status.last_synced_at) }}</template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
