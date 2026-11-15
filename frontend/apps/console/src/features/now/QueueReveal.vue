<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, formatCount, type OpState } from "@/ui";
import { hiddenParts, hiddenRows } from "./queueCap.ts";

/**
 * Now.md A2 'Over 100 open': one row-width button naming what the cut hides, by status. The row
 * is crit-tinted when something crit is out of sight. No 'less urgent' claim: priorities tie
 * across the cut (U20).
 */
const props = defineProps<{ items: readonly Readonly<{ state: OpState }>[] }>();
defineEmits<{ reveal: [] }>();
const hidden = computed(() => hiddenRows(props.items));
const parts = computed(() => (hidden.value ? hiddenParts(hidden.value) : []));
/** The dots and marks are visual only; the spoken name keeps the words apart. */
const label = computed(() =>
  hidden.value
    ? `Show ${formatCount(hidden.value.count)} more: ${parts.value.map((p) => p.text).join(", ")}`
    : "",
);
</script>

<template>
  <!-- One-off: a list row that is wholly a button; ApButton's chip shape can't fill a row. -->
  <li
    v-if="hidden"
    class="border-t border-hairline"
    :class="hidden.crit > 0 ? 'bg-[var(--apogee-wash-crit)]' : ''"
  >
    <button
      type="button"
      :aria-label="label"
      class="flex w-full flex-wrap items-center gap-x-2 gap-y-1 px-4 py-3 text-left font-mono text-xs text-readout uppercase cursor-pointer border-0 bg-transparent hover:bg-raised"
      @click="$emit('reveal')"
    >
      <span>Show {{ formatCount(hidden.count) }} more</span>
      <template v-for="part in parts" :key="part.text">
        <span aria-hidden="true" class="text-text-4">·</span>
        <span class="inline-flex items-center gap-1.5"
          ><ApStatusMark v-if="part.state" :state="part.state" />{{ part.text }}</span
        >
      </template>
    </button>
  </li>
</template>
