<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";

/** Inline contextual sentence: wash + mark + one sentence + optional trailing action. */
defineProps<{ tone: "nominal" | "caution" | "crit" | "stale" | "off" | "info" }>();
</script>

<template>
  <div
    :role="tone === 'crit' ? 'alert' : 'status'"
    class="flex items-center gap-3 px-4 py-2.5 text-base text-readout"
    :class="{
      'bg-[var(--apogee-wash-crit)]': tone === 'crit',
      'bg-[var(--apogee-wash-caution)]': tone === 'caution',
      'bg-[rgba(47,208,138,0.06)]': tone === 'nominal',
      'bg-[rgba(164,151,255,0.08)]': tone === 'stale',
      'bg-raised': tone === 'info' || tone === 'off',
    }"
  >
    <ApStatusMark v-if="tone !== 'info'" :state="tone" />
    <span class="min-w-0 flex-1"><slot /></span>
    <slot name="action" />
  </div>
</template>
