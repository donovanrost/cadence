<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, stateTextClass } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { constellation, limitLabel, limitMark, type HealthCell } from "../model/widget-data.ts";

/** Worst limit state per spacecraft. Counts lead, so the problems read first. */
const props = defineProps<{ placement: WorkspacePlacement }>();
const cells = computed(() => constellation(props.placement));
const order: readonly HealthCell["state"][] = ["red", "yellow", "blue", "no_data", "green"];
const counts = computed(() =>
  order
    .map((state) => ({ state, count: cells.value.filter((c) => c.state === state).length }))
    .filter(({ count }) => count > 0),
);
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-3 overflow-auto px-3 py-2">
    <ul class="flex flex-wrap gap-4 text-xs">
      <li v-for="{ state, count } in counts" :key="state" class="flex items-center gap-1.5">
        <ApStatusMark :state="limitMark[state]" />
        <span class="font-sans text-md tabular-nums" :class="stateTextClass(limitMark[state])">{{
          count
        }}</span>
        <span class="font-display uppercase tracking-tag text-text-3">{{ limitLabel[state] }}</span>
      </li>
    </ul>
    <ul class="flex flex-wrap gap-1.5" aria-label="Spacecraft health">
      <li
        v-for="cell in cells"
        :key="cell.id"
        class="grid h-5 w-5 place-items-center border border-hairline bg-vacuum"
        role="img"
        :title="`${cell.id}: ${limitLabel[cell.state]}`"
        :aria-label="`${cell.id}: ${limitLabel[cell.state]}`"
      >
        <ApStatusMark :state="limitMark[cell.state]" />
      </li>
    </ul>
  </div>
</template>
