<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";

/** States the fact, then one sentence on why / what next. Never an illustration. */
defineProps<{
  headline: string;
  sentence?: string | undefined;
  /** `off` = not set up (dashed mark). */
  state?: "off" | "stale" | undefined;
}>();
</script>

<template>
  <div class="flex flex-col items-start gap-2 px-4 py-6">
    <p class="ap-label flex items-center gap-2">
      <ApStatusMark v-if="state" :state="state" />{{ headline }}
    </p>
    <p v-if="sentence" class="m-0 max-w-[60ch] text-base leading-[1.55] text-text-3">
      {{ sentence }}
    </p>
    <div v-if="$slots.default" class="mt-1"><slot /></div>
  </div>
</template>
