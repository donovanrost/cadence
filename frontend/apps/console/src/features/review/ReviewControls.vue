<script setup lang="ts">
import { ApButton, ApSegmented, ApTimePicker } from "@/ui";
import type { Span } from "./api.ts";

/** K3 header controls: span, the day the window ends on, and Export CSV (time facts only). */
defineProps<{ span: Span; dayAt: number; canExport: boolean; exporting: boolean }>();
const emit = defineEmits<{ span: [span: Span]; day: [at: number | null]; export: [] }>();
const spans = [
  { value: "day", label: "Day" },
  { value: "week", label: "Week" },
  { value: "month", label: "Month" },
];
const setSpan = (v: string) => {
  if (v === "day" || v === "week" || v === "month") emit("span", v);
};
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <ApSegmented :model-value="span" label="Span" :options="spans" @update:model-value="setSpan" />
    <div class="w-[200px]">
      <ApTimePicker
        :model-value="dayAt"
        label="Ending"
        date-only
        @update:model-value="emit('day', $event)"
      />
    </div>
    <ApButton
      :disabled="!canExport || exporting"
      :disabled-reason="exporting ? 'Exporting…' : 'Waiting for the summary'"
      @click="emit('export')"
      >Export CSV</ApButton
    >
  </div>
</template>
