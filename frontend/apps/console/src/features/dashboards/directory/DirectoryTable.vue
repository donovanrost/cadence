<script setup lang="ts">
import { ApTable, type ApColumn } from "@/ui";
import { useSmallScreen } from "@/shell";
import type { DirectoryRow } from "./api.ts";
import DirectoryRows from "./DirectoryRows.vue";
import NameCell from "./NameCell.vue";
import RowActions from "./RowActions.vue";
import { spacecraftWord, updatedWord } from "./row-words.ts";

/**
 * ux: Name link · Tags · Spacecraft · Updated; secondary actions in the row's ⋯ (no whole-row
 * click). Below 768px it's the phone rows instead (qa §6 a11y).
 */
defineProps<{ rows: readonly DirectoryRow[]; canEdit: boolean }>();
const emit = defineEmits<{
  action: [action: "star" | "unstar" | "duplicate" | "archive" | "restore", row: DirectoryRow];
}>();
const small = useSmallScreen();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "tags", label: "Tags" },
  { key: "spacecraft", label: "Spacecraft" },
  { key: "updated", label: "Updated" },
  { key: "actions", label: "Actions", hiddenLabel: true, align: "end" },
];
</script>

<template>
  <DirectoryRows v-if="small" :rows="rows" @action="(a, row) => emit('action', a, row)" />
  <ApTable v-else :columns="columns" :rows="rows" :row-key="(r) => r.id" caption="Dashboards">
    <template #cell-name="{ row }"><NameCell :row="row" /></template>
    <template #cell-tags="{ row }"
      ><span class="text-text-3">{{ row.tags.join(", ") || "—" }}</span></template
    >
    <template #cell-spacecraft="{ row }"
      ><span class="text-text-3">{{ spacecraftWord(row) }}</span></template
    >
    <template #cell-updated="{ row }"
      ><span class="font-mono text-sm text-text-3">{{ updatedWord(row) }}</span></template
    >
    <template #cell-actions="{ row }">
      <RowActions :row="row" :can-edit="canEdit" @action="(a) => emit('action', a, row)" />
    </template>
  </ApTable>
</template>
