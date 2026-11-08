<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";
import type { OpState } from "./status.ts";

/** One event: time | mark | text. Use inside <ol class="m-0 list-none p-0">, newest first. */
defineProps<{ time: string; datetime?: string; state: OpState }>();
</script>

<template>
  <li class="grid grid-cols-[88px_14px_minmax(0,1fr)] items-baseline gap-2.5 px-4 py-1.5">
    <time class="font-mono text-sm text-text-4" :datetime="datetime">{{ time }}</time>
    <span class="self-center"><ApStatusMark :state="state" /></span>
    <span class="text-base text-text-2"><slot /></span>
  </li>
</template>
