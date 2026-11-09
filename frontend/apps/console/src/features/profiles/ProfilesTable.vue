<script setup lang="ts">
import { ApTable, formatCount, type ApColumn } from "@/ui";
import { protocolLine, type ProfileSummary } from "./api.ts";

/** Profile rows; the Name cell links to the profile page. */
defineProps<{ rows: readonly ProfileSummary[] }>();

const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "version", label: "Version", mono: true },
  { key: "spacecraft", label: "Spacecraft", mono: true, align: "end" },
  { key: "catalog", label: "Catalog", mono: true },
  { key: "protocols", label: "Protocols" },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(row) => row.id" caption="Profiles">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.profile', params: { profileId: row.id } }"
        class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-version="{ row }">v{{ row.version }}</template>
    <template #cell-spacecraft="{ row }">
      {{ formatCount(row.spacecraftCount) }}
      <span v-if="row.spacecraftOnOlderVersions > 0" class="block font-sans text-xs text-text-3"
        >{{ formatCount(row.spacecraftOnOlderVersions) }} on older versions</span
      >
    </template>
    <template #cell-catalog="{ row }">
      <span v-if="row.catalogRevision">rev {{ row.catalogRevision.number }}</span>
      <span v-else class="font-sans text-text-3">Set per spacecraft</span>
    </template>
    <template #cell-protocols="{ row }">
      <span class="text-text-2">{{ protocolLine(row) }}</span>
    </template>
  </ApTable>
</template>
