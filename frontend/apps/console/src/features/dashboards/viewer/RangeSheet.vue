<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet, ApTimeRange, useNow, type TimeRange } from "@/ui";
import { frozenBounds, quickRanges, type TimeSelection } from "../model/time-range.ts";

/** Picks the viewer range: a sliding quick range (≤24 h) or absolute bounds (≤31 days). */
const props = defineProps<{ selection: TimeSelection }>();
const emit = defineEmits<{ pick: [selection: TimeSelection] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const now = useNow();
// Seeded valid: the closed sheet's ApTimeRange is mounted, and a 0–0 range announced
// "To must be after From." (qa rerun 10:32Z).
const custom = ref<TimeRange>(frozenBounds(props.selection, now.value.getTime()));
const error = ref<string | null>(null);
const MAX_RANGE_MS = 31 * 86_400_000;

function open() {
  custom.value = frozenBounds(props.selection, now.value.getTime());
  error.value = null;
  sheet.value?.open();
}
function pick(selection: TimeSelection) {
  emit("pick", selection);
  sheet.value?.close();
}
function applyCustom() {
  const { from, to } = custom.value;
  if (to <= from) error.value = "The end must be after the start.";
  else if (to - from > MAX_RANGE_MS) error.value = "Ranges can span up to 31 days.";
  else
    pick({ kind: "absolute", from: new Date(from).toISOString(), to: new Date(to).toISOString() });
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Time range" initial-focus="[data-quick]">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-2">
        <ApButton
          v-for="r in quickRanges"
          :key="r.from"
          data-quick
          variant="secondary"
          size="compact"
          @click="pick({ kind: 'sliding', seconds: r.seconds })"
          >{{ r.label }}</ApButton
        >
      </div>
      <ApTimeRange v-model="custom" label="Absolute range" :presets="[]" />
      <p v-if="error" role="alert" class="m-0 text-sm text-crit-text">{{ error }}</p>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton variant="primary" @click="applyCustom">Apply range</ApButton>
    </template>
  </ApSheet>
</template>
