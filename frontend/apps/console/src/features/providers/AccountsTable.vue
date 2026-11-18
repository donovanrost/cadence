<script setup lang="ts">
import { ApTable, ApTag, formatShort, type ApColumn } from "@/ui";
import { statusTag, type ProviderAccount } from "./api.ts";

/** Provider accounts table: Name-cell link to the detail, status, missions, last call, added. */
defineProps<{ accounts: readonly ProviderAccount[] }>();
const columns: readonly ApColumn[] = [
  { key: "provider", label: "Provider" },
  { key: "name", label: "Account" },
  { key: "status", label: "Status" },
  { key: "missions", label: "Missions", mono: true, align: "end" },
  { key: "last", label: "Last successful call", mono: true },
  { key: "added", label: "Added" },
];
const when = (iso: string | null) => (iso ? formatShort(new Date(iso)) : "never");
</script>

<template>
  <ApTable :columns="columns" :rows="accounts" :row-key="(a) => a.id" caption="Provider accounts">
    <template #cell-provider="{ row }"
      >{{ row.provider.label
      }}<span class="ml-1.5 font-mono text-xs text-text-4">{{ row.provider.key }}</span></template
    >
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'org.provider-accounts', params: { accountId: row.id } }"
        class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-status="{ row }">
      <ApTag v-bind="statusTag(row)" />
      <span v-if="row.status_detail" class="block text-xs text-text-3">{{
        row.status_detail
      }}</span>
    </template>
    <template #cell-missions="{ row }">{{ row.missions.length }}</template>
    <template #cell-last="{ row }">{{ when(row.last_success_at) }}</template>
    <template #cell-added="{ row }"
      ><span class="text-text-3"
        >{{ when(row.added_at) }}{{ row.added_by?.name ? ` by ${row.added_by.name}` : "" }}</span
      ></template
    >
  </ApTable>
</template>
