<script setup lang="ts">
import { TopBarLevel, useTopBarLevel } from "./topbar-fit.ts";

const level = useTopBarLevel();
</script>

<template>
  <div class="flex items-center gap-3 border-r border-hairline px-4 md:px-[18px]">
    <svg width="20" height="20" viewBox="0 0 30 30" aria-hidden="true">
      <path d="M15 2 28 15 15 28 2 15Z" fill="none" stroke="currentColor" stroke-width="2" />
      <path d="M15 9 21 15 15 21 9 15Z" fill="currentColor" />
    </svg>
    <!-- Gives way first in the top bar (ux IA §Top bar): the mark stays, the name stays readable. -->
    <span
      class="font-display text-lg font-bold tracking-brand max-md:sr-only"
      :class="level >= TopBarLevel.brandMark ? 'sr-only' : ''"
      >CADENCE</span
    >
  </div>
</template>
