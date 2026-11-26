<script setup lang="ts">
import { ApButton, formatCount } from "@/ui";

/**
 * "Showing 200 of 1,204 active alarms, worst first" with Load more (#827): shown whenever a paged
 * alarm list holds only part of what matches, so it never looks complete when it isn't. Failure
 * to load more is said next to the button as an alert, always mounted so it is announced; the
 * rows stay (ux U72, a11y B6).
 */
defineProps<{
  shown: number;
  total: number;
  /** What the alarms are, for the sentence: "active alarms on EARENDIL-008". */
  what: string;
  busy: boolean;
  failed: boolean;
}>();
defineEmits<{ more: [] }>();
</script>

<template>
  <div class="flex flex-wrap items-center gap-3">
    <p class="m-0 font-mono text-xs text-text-3 uppercase">
      Showing {{ formatCount(shown) }} of {{ formatCount(total) }} {{ what }}, worst first
    </p>
    <ApButton
      size="compact"
      variant="secondary"
      :disabled="busy"
      disabled-reason="Loading…"
      @click="$emit('more')"
      >Load more</ApButton
    >
    <span role="alert" class="text-sm text-caution-text">{{
      failed ? "More alarms couldn't load. Try Load more again." : ""
    }}</span>
  </div>
</template>
