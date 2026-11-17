<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, ApPanel, ApTable, type ApColumn } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { comparisonRows, DRAFT_MATCHES, NOTHING_ACTIVE, type ComparisonRow } from "./words.ts";

/** U94 Changes: Setting / Active / Draft; nothing active reads as U90 (every setting is new). */
const props = defineProps<{ snapshot: ConfigurationSnapshot }>();
const rows = computed(() => comparisonRows(props.snapshot));
const columns: readonly ApColumn[] = [
  { key: "setting", label: "Setting" },
  { key: "active", label: "Active" },
  { key: "draft", label: "Draft" },
];
const keyOf = (r: ComparisonRow) => r.setting;
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
    />
  </ApPanel>
</template>
