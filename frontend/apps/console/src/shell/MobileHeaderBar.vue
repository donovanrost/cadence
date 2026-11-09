<script setup lang="ts">
import { formatClock, useNow } from "@/ui";
import type { MobileHeader } from "./mobile-header.ts";

defineProps<{ header: MobileHeader }>();
const now = useNow();
</script>

<template>
  <div class="flex min-w-0 flex-1 items-stretch">
    <RouterLink
      v-if="header.back"
      :to="header.back"
      aria-label="Back"
      class="flex w-14 flex-none items-center justify-center border-r border-hairline text-readout"
    >
      <svg
        aria-hidden="true"
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2.5"
      >
        <path d="m15 6-6 6 6 6" />
      </svg>
    </RouterLink>
    <div class="flex min-w-0 flex-1 flex-col justify-center px-4">
      <span v-if="header.context" class="truncate font-mono text-xs text-text-4 uppercase">{{
        header.context
      }}</span>
      <span class="truncate font-display text-lg font-semibold tracking-tag uppercase">{{
        header.title
      }}</span>
    </div>
    <time class="flex items-center px-3 font-mono text-sm tabular" :datetime="now.toISOString()"
      >{{ formatClock(now).slice(0, 5) }}Z</time
    >
  </div>
</template>
