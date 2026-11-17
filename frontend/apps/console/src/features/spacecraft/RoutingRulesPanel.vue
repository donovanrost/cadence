<script setup lang="ts">
import { computed } from "vue";
import { ApEmptyState, ApPanel, ApTable, type ApColumn } from "@/ui";
import { directionLabel, type RoutingRule } from "./detail.ts";

/** D4 Routing rules for this spacecraft (per spacecraft until DECISIONS #3 moves them to the profile). */
const props = defineProps<{ rules: readonly RoutingRule[] }>();
const active = computed(() => props.rules.filter((r) => r.active));
const columns: readonly ApColumn[] = [
  { key: "name", label: "Rule" },
  { key: "direction", label: "Direction" },
  { key: "role", label: "Role" },
  { key: "transport", label: "Transport" },
  { key: "state", label: "State" },
];
</script>

<template>
  <ApPanel index="D4" title="Routing" flush>
    <template #meta>
      {{ active.length }} active ·
      <RouterLink
        :to="{ name: 'setup.comms' }"
        class="text-readout no-underline hover:text-bright max-md:hit-44"
        >Comms &amp; routing →</RouterLink
      >
    </template>
    <ApEmptyState
      v-if="active.length === 0"
      state="off"
      headline="No routing rule"
      sentence="It can't be contacted until a routing rule covers it."
    />
    <ApTable
      v-else
      :columns="columns"
      :rows="active"
      :row-key="(r) => r.id"
      caption="Routing rules"
    >
      <template #cell-name="{ row }">
        {{ row.name }}<span v-if="row.purpose" class="text-text-4"> · {{ row.purpose }}</span>
      </template>
      <template #cell-direction="{ row }">{{ directionLabel(row.direction) }}</template>
      <template #cell-role="{ row }"
        ><span class="capitalize">{{ row.role }}</span></template
      >
      <template #cell-transport="{ row }">{{ row.transport.name }}</template>
      <template #cell-state="{ row }">
        <span :class="row.enabled ? 'text-text-3' : 'text-caution-text'">{{
          row.enabled ? "Enabled" : "Disabled"
        }}</span>
      </template>
    </ApTable>
  </ApPanel>
</template>
