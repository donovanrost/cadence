<script setup lang="ts">
import { RouterLink } from "vue-router";
import { ApTable, formatShort, type ApColumn } from "@/ui";
import type { DirectoryRow } from "./api.ts";
import RowActions from "./RowActions.vue";

/** ux: Name link · Tags · Spacecraft · Updated; secondary actions in the row's ⋯ (no whole-row click). */
defineProps<{ rows: readonly DirectoryRow[]; canEdit: boolean }>();
const emit = defineEmits<{
  action: [action: "star" | "unstar" | "duplicate" | "archive" | "restore", row: DirectoryRow];
}>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "tags", label: "Tags" },
  { key: "spacecraft", label: "Spacecraft" },
  { key: "updated", label: "Updated" },
  { key: "actions", label: "Actions", hiddenLabel: true, align: "end" },
];
function spacecraft(row: DirectoryRow): string {
  const s = row.spacecraft;
  if (s === undefined) return "—";
  if (s === null) return "No widgets";
  switch (s.mode) {
    case "fixed":
      return s.spacecraft?.name ?? "One spacecraft";
    case "context":
      return "Chosen when viewing";
    case "fleet":
      return "Whole fleet";
    case "mixed":
      return "Mixed";
  }
}
const updated = (row: DirectoryRow) =>
  row.updated_at
    ? `${formatShort(new Date(row.updated_at))}${row.updated_by?.name ? ` · ${row.updated_by.name}` : ""}`
    : "—";
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(r) => r.id" caption="Dashboards">
    <template #cell-name="{ row }">
      <span class="flex items-center gap-2">
        <span v-if="row.starred" class="text-text-3" aria-label="Starred">★</span>
        <RouterLink
          :to="{ name: 'ops.dashboard', params: { dashboardId: row.id } }"
          class="text-readout underline-offset-2 hover:underline"
          >{{ row.name }}</RouterLink
        >
        <span v-if="row.archived" class="font-display text-xs uppercase tracking-tag text-text-4"
          >Archived</span
        >
      </span>
    </template>
    <template #cell-tags="{ row }"
      ><span class="text-text-3">{{ row.tags.join(", ") || "—" }}</span></template
    >
    <template #cell-spacecraft="{ row }"
      ><span class="text-text-3">{{ spacecraft(row) }}</span></template
    >
    <template #cell-updated="{ row }"
      ><span class="font-mono text-sm text-text-3">{{ updated(row) }}</span></template
    >
    <template #cell-actions="{ row }">
      <RowActions :row="row" :can-edit="canEdit" @action="(a) => emit('action', a, row)" />
    </template>
  </ApTable>
</template>
