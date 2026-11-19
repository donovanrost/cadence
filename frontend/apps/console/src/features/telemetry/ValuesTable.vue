<script setup lang="ts">
import { formatClock, ApPanel, ApTable, type ApColumn } from "@/ui";
import { formatValue, withUnit } from "@/features/alarms/index.ts";
import type { latestRows } from "./plot.ts";

/** T3 · Latest bucket per series (mean, with the bucket's start time). */
defineProps<{ rows: ReturnType<typeof latestRows> }>();
const columns: readonly ApColumn[] = [
  { key: "series", label: "Series" },
  { key: "value", label: "Latest (bucket mean)", mono: true, align: "end" },
  { key: "range", label: "Min – max", mono: true, align: "end" },
  { key: "at", label: "Bucket", mono: true },
];
</script>

<template>
  <ApPanel index="T3" title="Values" pane flush class="h-[180px] flex-none">
    <ApTable :columns="columns" :rows="rows" :row-key="(r) => r.key" caption="Latest values">
      <template #cell-series="{ row }"
        ><span class="font-mono normal-case">{{ row.label }}</span></template
      >
      <template #cell-value="{ row }">{{
        row.last ? withUnit(formatValue(row.last.mean), row.unit) : "—"
      }}</template>
      <template #cell-range="{ row }">{{
        row.last ? `${formatValue(row.last.min)} – ${formatValue(row.last.max)}` : "—"
      }}</template>
      <template #cell-at="{ row }">{{
        row.last ? `${formatClock(new Date(row.last.t))}Z` : "no data in window"
      }}</template>
    </ApTable>
  </ApPanel>
</template>
