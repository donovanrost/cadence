<script setup lang="ts">
import { computed } from "vue";
import { usePalette } from "./palette.ts";
import { TopBarLevel, useTopBarLevel } from "./topbar-fit.ts";

defineProps<{ placeholder: string }>();
const palette = usePalette();
/** The bar's flexible item: one line down to 160px, then the '⌕ ⌘K' icon button named "Search". */
const level = useTopBarLevel();
const icon = computed(() => level.value >= TopBarLevel.queryIcon);
</script>

<template>
  <button
    type="button"
    data-topbar-flex
    :aria-label="icon ? 'Search' : undefined"
    class="flex cursor-pointer items-center gap-2.5 border-0 border-r border-hairline bg-transparent text-left text-base whitespace-nowrap text-text-4 hover:bg-raised"
    :class="icon ? 'flex-none px-3.5' : 'min-w-[160px] flex-[1_1_240px] px-[18px]'"
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
    <!-- One line, truncating as the bar tightens; an icon button at its give-way step (ux IA §Top bar). -->
    <span v-if="!icon" class="min-w-0 flex-1 truncate">{{ placeholder }}</span>
    <kbd class="border border-line px-1.5 py-px font-mono text-xs text-text-3">⌘K</kbd>
  </button>
</template>
