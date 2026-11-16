<script setup lang="ts">
import { ApButton, formatShort } from "@/ui";
import type { Change } from "./shapes.ts";

/** K1 row head: summary, author and staged time, Withdraw (when allowed), Details toggle. */
defineProps<{ change: Change; canWithdraw: boolean; open: boolean; busy: boolean }>();
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
      :aria-label="`Withdraw ${change.summary}`"
      :disabled="busy"
      disabled-reason="Working…"
      @click="$emit('withdraw')"
      >Withdraw</ApButton
    >
    <ApButton size="compact" variant="ghost" :aria-expanded="open" @click="$emit('toggle')">{{
      open ? "Hide" : "Details"
    }}</ApButton>
  </div>
</template>
