<script setup lang="ts">
import { ApStatusMark, ApTable, formatShort, type ApColumn } from "@/ui";
import type { MissionProvider } from "./api.ts";
import EphemerisCounts from "./EphemerisCounts.vue";
import { grantLine, healthLine } from "./providers.ts";

/** The mission's providers; the name opens the provider (L12 Validate / Sync / Archive). */
defineProps<{ providers: readonly MissionProvider[] }>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Provider" },
  { key: "account", label: "Account" },
  { key: "stations", label: "Stations", mono: true, align: "end" },
  { key: "health", label: "Health" },
  { key: "orbits", label: "Orbits" },
  { key: "synced", label: "Last synced", mono: true },
];
const when = (at: string | null) => (at ? formatShort(new Date(at)) : "never");
</script>

<template>
  <ApTable :columns="columns" :rows="providers" :row-key="(p) => p.id" caption="Providers">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.stations.providers', params: { providerId: row.id } }"
        class="font-semibold text-primary no-underline hover:underline max-md:hit-44"
        >{{ row.name }}</RouterLink
      >
      <span class="font-mono text-xs text-text-3"> {{ row.provider_type }}</span>
      <span v-if="grantLine(row.grant).revoked" class="text-xs text-crit-text">
        · Account grant {{ grantLine(row.grant).text }}</span
      >
    </template>
    <template #cell-account="{ row }">{{
      row.account ? (row.account.name ?? "Org admins only") : "—"
    }}</template>
    <template #cell-stations="{ row }">{{ row.station_count }}</template>
    <template #cell-health="{ row }"
      ><span class="inline-flex items-center gap-2"
        ><ApStatusMark :state="healthLine(row.health.validate).state" />{{
          healthLine(row.health.validate).text
        }}</span
      ></template
    >
    <template #cell-orbits="{ row }"
      ><EphemerisCounts :ephemeris="row.ephemeris" :provider-id="row.id"
    /></template>
    <template #cell-synced="{ row }">{{ when(row.status.last_synced_at) }}</template>
  </ApTable>
</template>
