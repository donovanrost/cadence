<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";
import type { OpState } from "./status.ts";

/** Progress pills joined by arrows. Progress states are gray; only outcomes carry a mark. */
export type ApTrailStep = Readonly<{
  label: string;
  outcome?: Exclude<OpState, "neutral" | "optional">;
}>;
defineProps<{ steps: readonly ApTrailStep[]; label: string }>();
</script>

<template>
  <ol :aria-label="label" class="m-0 flex list-none flex-wrap items-center gap-2 p-0">
    <li v-for="(step, i) in steps" :key="`${i}-${step.label}`" class="flex items-center gap-2">
      <span v-if="i > 0" aria-hidden="true" class="text-line-strong">→</span>
      <span
        class="inline-flex h-[30px] items-center gap-2 border border-line bg-raised px-2.5 font-display text-md font-semibold tracking-tag text-text-2 uppercase"
      >
        <ApStatusMark v-if="step.outcome" :state="step.outcome" />{{ step.label }}
      </span>
    </li>
  </ol>
</template>
