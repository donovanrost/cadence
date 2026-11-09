<script setup lang="ts">
import { ApStatusMark, ApTable, formatCount, type ApColumn } from "@/ui";
import type { Station } from "./api.ts";

/** Ground stations; health is "not reported" until the server tracks it (never assumed ok). */
defineProps<{ rows: readonly Station[] }>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Station" },
  { key: "code", label: "Code", mono: true },
  { key: "provider", label: "Provider" },
  { key: "region", label: "Region" },
  { key: "transports", label: "Transports", mono: true, align: "end" },
  { key: "rules", label: "Routing rules", mono: true, align: "end" },
  { key: "health", label: "Health" },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(s) => s.id" caption="Ground stations">
    <template #cell-name="{ row }">
      <span class="font-semibold text-readout">{{ row.display_name }}</span>
      <span v-if="row.lifecycle_state === 'archived'" class="text-xs text-text-4"> · archived</span>
    </template>
    <template #cell-code="{ row }">{{ row.code ?? "—" }}</template>
    <template #cell-provider="{ row }">{{ row.provider ?? "—" }}</template>
    <template #cell-region="{ row }">{{ row.region ?? "—" }}</template>
    <template #cell-transports="{ row }">{{ formatCount(row.transport_count) }}</template>
    <template #cell-rules="{ row }">{{ formatCount(row.routing_rule_count) }}</template>
    <template #cell-health="{ row }">
      <span v-if="row.health === null" class="inline-flex items-center gap-2 text-text-3"
        ><ApStatusMark state="off" />Not reported</span
      >
      <span v-else class="inline-flex items-center gap-2"
        ><ApStatusMark
          :state="
            row.health.status === 'nominal'
              ? 'nominal'
              : row.health.status === 'degraded'
                ? 'caution'
                : 'crit'
          "
        />{{
          row.health.status === "nominal"
            ? "Nominal"
            : row.health.status === "degraded"
              ? "Degraded"
              : "Down"
        }}</span
      >
    </template>
  </ApTable>
</template>
