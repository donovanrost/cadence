<script setup lang="ts">
import { computed, ref } from "vue";
import CommandKit from "./CommandKit.vue";
import GanttKit from "./GanttKit.vue";
import MenuKit from "./MenuKit.vue";
import TableKit from "./TableKit.vue";
import {
  ApPageHeader,
  ApPanel,
  ApTimePicker,
  ApTimeRange,
  useNow,
  type RangePreset,
  type TimePreset,
  type TimeRange,
} from "@/ui";

/**
 * Development-only review page for shared components that have no consuming screen yet.
 * Sample values are clearly fixtures; this route is not registered in production builds.
 */
const now = useNow();
const at = ref<number | null>(null);
const presets = computed<TimePreset[]>(() => {
  const t = now.value.getTime();
  return [
    { id: "now", label: "Now", at: t, sub: "Send as soon as possible" },
    { id: "plus1h", label: "+1 hour", at: t + 3_600_000, sub: "Fixture preset" },
    {
      id: "shift",
      label: "Shift change",
      at: Math.ceil(t / 21_600_000) * 21_600_000,
      sub: "Next 6-hour boundary",
    },
  ];
});
const rangePresets = computed<RangePreset[]>(() => {
  const t = Math.floor(now.value.getTime() / 60_000) * 60_000;
  return [
    { id: "h1", label: "Last 1h", from: t - 3_600_000, to: t },
    { id: "h6", label: "Last 6h", from: t - 21_600_000, to: t },
    { id: "h24", label: "24h", from: t - 86_400_000, to: t },
  ];
});
const plotWindow = ref<TimeRange>({ from: Date.now() - 21_600_000, to: Date.now() });
const today = computed(() => now.value.toISOString().slice(0, 10));
const warn = (t: number) =>
  t < now.value.getTime() - 1000
    ? "That time is in the past. The uplink would release immediately."
    : null;
</script>

<template>
  <div class="flex max-w-[1100px] flex-col gap-4">
    <ApPageHeader label="Development · component review" title="Kit" size="reading" />
    <ApPanel index="K1" title="ApTimePicker" meta="FIXTURE PRESETS">
      <div class="max-w-[520px]">
        <ApTimePicker
          v-model="at"
          label="Release at"
          :presets="presets"
          :marked-days="[today]"
          :warn="warn"
        />
      </div>
    </ApPanel>
    <ApPanel index="K2" title="ApTimeRange" meta="FIXTURE PRESETS · NO BANDS">
      <ApTimeRange v-model="plotWindow" label="Plot window" :presets="rangePresets" />
    </ApPanel>
    <CommandKit />
    <GanttKit />
    <TableKit />
    <MenuKit />
  </div>
</template>
