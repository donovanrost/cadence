<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApPanel, ApStatusMark, ApTable, formatCount, type ApColumn } from "@/ui";
import { orbitLabel } from "../format.ts";
import { rangeLabel, type ProposedSpacecraft } from "./batch.ts";

/** A3 Batch preview: first 8 rows, then all on request. Rows with problems get a caution wash. */
const props = defineProps<{ rows: readonly ProposedSpacecraft[] }>();
const showAll = ref(false);
const shown = computed(() => (showAll.value ? props.rows : props.rows.slice(0, 8)));
const rest = computed(() => props.rows.slice(8));

const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "scid", label: "SCID", mono: true, align: "end" },
  { key: "norad", label: "NORAD", mono: true, align: "end" },
  { key: "orbit", label: "Plane · slot", mono: true },
  { key: "problems", label: "Check" },
  { key: "first", label: "First state" },
];
</script>

<template>
  <ApPanel
    index="A3"
    title="Batch preview"
    :meta="`${formatCount(rows.length)} new · showing ${formatCount(shown.length)}`"
    flush
  >
    <ApTable
      :columns="columns"
      :rows="shown"
      :row-key="(r) => r.key"
      caption="Spacecraft to create"
      :row-state="(r) => (r.problems.length > 0 ? 'caution' : null)"
    >
      <!-- A row from the file, not a craft yet: a blank name reads Unnamed, never a dash (rule 5). -->
      <template #cell-name="{ row }">
        <span v-if="row.name.trim()" class="font-semibold">{{ row.name }}</span>
        <span v-else class="text-caution-text">Unnamed</span>
      </template>
      <template #cell-scid="{ row }">
        <span v-if="row.scid !== null">{{ row.scid }}</span>
        <span v-else class="text-caution-text">not set</span>
      </template>
      <template #cell-norad="{ row }">
        <span v-if="row.norad !== null">{{ row.norad }}</span>
        <span v-else class="text-caution-text">not set</span>
      </template>
      <template #cell-orbit="{ row }">{{ orbitLabel(row.plane, row.slot) ?? "—" }}</template>
      <template #cell-problems="{ row }">
        <span v-if="row.problems.length === 0" class="text-text-3">OK</span>
        <span v-else class="text-caution-text">{{ row.problems.join("; ") }}</span>
      </template>
      <template #cell-first>
        <span class="inline-flex items-center gap-2 text-text-3"
          ><ApStatusMark state="off" />Awaiting first AOS</span
        >
      </template>
    </ApTable>
    <div
      v-if="rest.length > 0"
      class="flex items-center justify-between gap-3 border-t border-hairline px-4 py-2.5"
    >
      <span class="text-sm text-text-3"
        >{{ formatCount(rest.length) }} more rows · {{ rangeLabel(rest) }}</span
      >
      <ApButton size="compact" :aria-expanded="showAll" @click="showAll = !showAll">{{
        showAll ? "Show first 8" : `Show all ${formatCount(rows.length)}`
      }}</ApButton>
    </div>
  </ApPanel>
</template>
