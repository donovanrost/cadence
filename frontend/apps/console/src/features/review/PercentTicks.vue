<script setup lang="ts">
/** R3's 0–100% value axis (ux §7 #3): hairline ticks with labels left of the plot. */
const ticks = [0, 50, 100] as const;
</script>

<template>
  <div
    v-for="t in ticks"
    :key="t"
    class="absolute inset-x-0 border-t border-hairline"
    :style="{ bottom: `${t}%` }"
    aria-hidden="true"
  >
    <span class="absolute -left-10 w-8 -translate-y-1/2 text-right font-mono text-xs text-text-3"
      >{{ t }}%</span
    >
  </div>
</template>
