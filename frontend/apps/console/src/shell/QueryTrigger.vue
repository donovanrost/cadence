<script setup lang="ts">
import { usePalette } from "./palette.ts";

defineProps<{ placeholder: string }>();
const palette = usePalette();
</script>

<template>
  <button
    type="button"
    class="flex flex-[1_1_240px] cursor-pointer items-center gap-2.5 border-0 border-r border-hairline bg-transparent px-[18px] text-left text-base text-text-4 hover:bg-raised"
    aria-keyshortcuts="Meta+K Control+K /"
    @click="palette.show"
  >
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      aria-hidden="true"
    >
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
    <span class="flex-1">{{ placeholder }}</span>
    <kbd class="border border-line px-1.5 py-px font-mono text-xs text-text-3">⌘K</kbd>
  </button>
</template>
