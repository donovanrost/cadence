<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, ApPanel, ApTable, type ApColumn } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { comparisonRows, DRAFT_MATCHES, NOTHING_ACTIVE, type ComparisonRow } from "./words.ts";

/**
 * U94 Changes: Setting / Active / Draft. A first start drops the Active column (U90's line says
 * nothing is active); literal values (APIDs, framing) read in mono.
 */
const props = defineProps<{ snapshot: ConfigurationSnapshot }>();
const rows = computed(() => comparisonRows(props.snapshot));
const columns = computed((): readonly ApColumn[] => [
  { key: "setting", label: "Setting" },
  ...(props.snapshot.active ? [{ key: "active", label: "Active" }] : []),
  { key: "draft", label: "Draft" },
]);
const keyOf = (r: ComparisonRow) => r.setting;
const cell = (r: ComparisonRow, key: string) =>
  key === "active" ? r.active : key === "draft" ? r.draft : r.setting;
</script>

<template>
  <ApPanel index="C3" title="Changes" flush>
    <ApCallout v-if="snapshot.active === null" tone="info">{{ NOTHING_ACTIVE }}</ApCallout>
    <p v-if="rows.length === 0" class="m-0 px-4 py-3 text-md text-text-2">{{ DRAFT_MATCHES }}</p>
    <ApTable
      v-else
      :columns="columns"
      :rows="rows"
      :row-key="keyOf"
      caption="The draft compared with the active configuration"
    >
      <template #cell="{ row, column }">
        <span :class="row.mono && column.key !== 'setting' ? 'font-mono' : undefined">{{
          cell(row, column.key)
        }}</span>
      </template>
    </ApTable>
  </ApPanel>
</template>
