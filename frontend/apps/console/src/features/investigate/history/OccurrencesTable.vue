<script setup lang="ts">
import { ApTable, type ApColumn } from "@/ui";
import { durationWords, howItEnded, shortTime, valueWords, type Occurrence } from "./api.ts";

/** H3 · Prior occurrences (Investigate.md §History): newest first, how each one ended. */
defineProps<{ items: readonly Occurrence[] }>();
const columns: readonly ApColumn[] = [
  { key: "opened", label: "Opened", mono: true },
  { key: "cleared", label: "Cleared", mono: true },
  { key: "duration", label: "Duration", mono: true },
  { key: "values", label: "First → last", mono: true },
  { key: "ack", label: "Acknowledged by" },
  { key: "ended", label: "How it ended" },
];
</script>

<template>
  <ApTable :columns="columns" :rows="items" :row-key="(row) => row.id" caption="Prior occurrences">
    <template #cell-opened="{ row }">{{ shortTime(row.opened_at) }}</template>
    <template #cell-cleared="{ row }">{{
      row.cleared_at ? shortTime(row.cleared_at) : "—"
    }}</template>
    <template #cell-duration="{ row }">{{ durationWords(row) ?? "Open" }}</template>
    <template #cell-values="{ row }"
      >{{ valueWords(row.first_value, row.point.unit) }} →
      {{ valueWords(row.last_value, row.point.unit) }}</template
    >
    <template #cell-ack="{ row }">{{ row.acknowledged_by?.name ?? "—" }}</template>
    <template #cell-ended="{ row }">{{ howItEnded(row) }}</template>
  </ApTable>
</template>
