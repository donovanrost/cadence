<script setup lang="ts">
import { formatClock, useNow } from "@/lib/index.ts";

/** UTC always. AOS and MET join only when real data exists (decisions U7 / D4); CONFIG rN with change sets (D1). */
const now = useNow();
</script>

<template>
  <div class="flex items-center gap-[22px] px-[18px] font-mono text-md">
    <slot />
    <span>
      <span class="text-text-4">UTC</span>
      <time class="tabular" :datetime="now.toISOString()"> {{ formatClock(now) }}</time>
    </span>
  </div>
</template>
