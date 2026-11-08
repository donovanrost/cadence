<script setup lang="ts">
import { formatClock, useNow } from "@/ui";

/** UTC always. AOS and MET join only when real data exists (decisions U7 / D4); CONFIG rN with change sets (D1). */
const now = useNow();
</script>

<template>
  <div class="flex items-center gap-[22px] px-3 font-mono text-md md:px-[18px]">
    <slot />
    <span class="flex gap-[0.6em]">
      <span class="text-text-4">UTC</span>
      <time class="tabular" :datetime="now.toISOString()">{{ formatClock(now) }}</time>
    </span>
  </div>
</template>
