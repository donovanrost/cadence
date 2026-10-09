<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../../workspace/contracts";
import { constellation, limitLabel, type HealthCell } from "../widget-data";

const props = defineProps<{ placement: WorkspacePlacement }>();
const cells = computed(() => constellation(props.placement));
const order = ["red", "yellow", "blue", "green", "no_data"] as const;
const tone: Record<HealthCell["state"], string> = {
  red: "bg-error",
  yellow: "bg-warning",
  blue: "bg-info",
  green: "bg-success/70",
  no_data: "bg-base-content/20",
};
const label = (state: HealthCell["state"]) => (state === "no_data" ? "No data" : limitLabel[state]);
const counts = computed(() =>
  order
    .map((state) => ({ state, count: cells.value.filter((c) => c.state === state).length }))
    .filter(({ count }) => count > 0),
);
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-3 overflow-auto px-3 py-2">
    <ul class="flex flex-wrap gap-3 text-xs">
      <li v-for="{ state, count } in counts" :key="state" class="flex items-center gap-1.5">
        <span class="h-2.5 w-2.5 rounded-sm" :class="tone[state]" aria-hidden="true"></span>
        <span class="font-mono font-semibold tabular-nums">{{ count }}</span>
        <span class="text-base-content/70">{{ label(state) }}</span>
      </li>
    </ul>
    <ul class="flex flex-wrap gap-1" aria-label="Spacecraft health">
      <li
        v-for="cell in cells"
        :key="cell.id"
        class="h-4 w-4 rounded-sm"
        :class="tone[cell.state]"
        role="img"
        :title="`${cell.id}: ${label(cell.state)}`"
        :aria-label="`${cell.id}: ${label(cell.state)}`"
      ></li>
    </ul>
  </div>
</template>
