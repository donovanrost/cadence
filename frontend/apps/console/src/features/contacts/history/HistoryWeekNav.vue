<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { ApButton, ApTimePicker } from "@/ui";
import { DAY_MS, isoDay, mondayOf, stepWeek, type WeekSpan } from "./history.ts";
import { weekLabel } from "./words.ts";

/**
 * U78 stepper: '‹ Older week' · '11-09 – 11-15' · 'Newer week ›', a 'This week' link off the
 * current week, and 'Go to date' (any day; it opens that day's week; the future is refused).
 */
const props = defineProps<{ week: string; span: WeekSpan; now: number }>();
const emit = defineEmits<{ week: [week: string | undefined] }>();
const older = computed(() => stepWeek(props.week, -1, props.now));
const newer = computed(() => stepWeek(props.week, 1, props.now));
const today = computed(() => Math.floor(props.now / DAY_MS) * DAY_MS);
const future = (at: number) => (at > today.value ? "Pick a date up to today." : null);
/** A refused future date says why under the field, not only inside the picker (qa, U78). */
const refused = ref<string | null>(null);
watch(
  () => props.week,
  () => (refused.value = null),
);
const goTo = (at: number | null) => {
  if (at === null) return;
  refused.value = future(at);
  if (refused.value === null) emit("week", isoDay(mondayOf(at)));
};
</script>

<template>
  <div class="flex flex-wrap items-end gap-2">
    <ApButton size="standard" :disabled="older === null" @click="emit('week', older ?? undefined)"
      >‹ Older week</ApButton
    >
    <p class="m-0 self-center px-1 font-mono text-sm text-readout">{{ weekLabel(span, now) }}</p>
    <ApButton
      size="standard"
      :disabled="newer === null"
      disabled-reason="This is the current week."
      @click="emit('week', newer ?? undefined)"
      >Newer week ›</ApButton
    >
    <ApButton v-if="!span.current" size="standard" variant="ghost" @click="emit('week', undefined)"
      >This week</ApButton
    >
    <div class="w-[230px]">
      <ApTimePicker
        :model-value="span.from"
        label="Go to date"
        date-only
        :warn="future"
        @update:model-value="goTo"
      />
      <p role="status" class="m-0 mt-1 text-sm text-caution-text">{{ refused }}</p>
    </div>
  </div>
</template>
