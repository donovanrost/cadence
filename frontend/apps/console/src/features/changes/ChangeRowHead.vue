<script setup lang="ts">
import { computed } from "vue";
import { ApButton, formatShort } from "@/ui";
import type { Change } from "./shapes.ts";

/**
 * K1 row head: summary, author and staged time, Withdraw (when allowed), Details toggle. #313 K9
 * (ux §10; a11y B7): Withdraw is the `×`, named and titled "Withdraw <change> from r<next>".
 */
const props = defineProps<{
  change: Change;
  canWithdraw: boolean;
  open: boolean;
  busy: boolean;
  /** The revision this set applies as (head + 1). */
  nextRevision: number;
}>();
const withdrawName = computed(() => `Withdraw ${props.change.summary} from r${props.nextRevision}`);
defineEmits<{ withdraw: []; toggle: [] }>();
</script>

<template>
  <div
    class="grid grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-3 px-4 py-3 max-md:grid-cols-1 max-md:gap-1.5"
  >
    <span data-change-row class="text-base font-semibold text-readout">{{ change.summary }}</span>
    <span class="text-sm text-text-3"
      >{{ change.author.name }} ·
      <time class="font-mono text-xs" :datetime="change.staged_at">{{
        formatShort(new Date(change.staged_at))
      }}</time></span
    >
    <ApButton
      v-if="canWithdraw"
      size="compact"
      variant="ghost"
      data-withdraw
      :aria-label="withdrawName"
      :title="withdrawName"
      :disabled="busy"
      disabled-reason="Working…"
      @click="$emit('withdraw')"
      ><span aria-hidden="true">×</span></ApButton
    >
    <ApButton size="compact" variant="ghost" :aria-expanded="open" @click="$emit('toggle')">{{
      open ? "Hide" : "Details"
    }}</ApButton>
  </div>
</template>
