<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../../workspace/contracts";
import { table, type LimitState } from "../widget-data";

const props = defineProps<{ placement: WorkspacePlacement }>();
const data = computed(() => table(props.placement));
const cellTone: Record<LimitState, string> = {
  red: "bg-error/15 text-error",
  yellow: "bg-warning/15 text-warning",
  blue: "bg-info/15 text-info",
  green: "text-success",
};
</script>

<template>
  <div class="h-full min-h-0 overflow-auto">
    <table class="w-full border-collapse text-xs">
      <thead class="sticky top-0 bg-base-200">
        <tr>
          <th
            v-for="column in data.columns"
            :key="column.key"
            scope="col"
            class="whitespace-nowrap border-b border-base-300 px-2 py-1.5 text-left font-medium text-base-content/70 capitalize"
          >
            {{ column.label }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in data.rows" :key="row.key" class="hover:bg-base-300/30">
          <td
            v-for="cell in row.cells"
            :key="cell.key"
            class="whitespace-nowrap border-b border-base-300/40 px-2 py-1 font-mono tabular-nums"
            :class="cell.state ? cellTone[cell.state] : ''"
          >
            {{ cell.text }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
