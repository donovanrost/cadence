<script setup lang="ts">
import { showValue } from "./api.ts";
import type { RevisionEntry } from "./shapes.ts";

/** One entity's field rows: `label  before → after` (Changes.md §4; Profile History reuses it). */
defineProps<{ fields: RevisionEntry["fields"] }>();
</script>

<template>
  <ul class="m-0 mt-1.5 flex list-none flex-col gap-0.5 p-0 text-sm">
    <li v-for="f in fields" :key="f.path" class="grid grid-cols-[minmax(0,240px)_1fr] gap-3">
      <span class="truncate text-text-3" :title="f.path">{{ f.label ?? f.path }}</span>
      <span
        class="truncate font-mono"
        :title="`${showValue(f.before, f.unit, f.format)} → ${showValue(f.after, f.unit, f.format)}`"
        ><span class="text-text-3">{{ showValue(f.before, f.unit, f.format) }}</span> →
        <span class="text-readout">{{ showValue(f.after, f.unit, f.format) }}</span></span
      >
    </li>
  </ul>
</template>
