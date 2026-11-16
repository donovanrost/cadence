<script setup lang="ts">
/**
 * One end of the range track's window (ux U62): a 2px readout bar the full height with a 12×20 grip
 * (two hairlines) at its middle. The hit area is 24px with a fine pointer and 44px with a coarse
 * one, centred on the edge; when the band is under 16px wide the handle sits outside its end so
 * the body stays grabbable. A slider: arrows, Shift/PgUp/PgDn, Home/End (the track handles keys).
 */
defineProps<{
  part: "start" | "end";
  /** Position along the track, 0–100. */
  pct: number;
  /** 'From 11-14 03:10Z' */
  valueText: string;
  value: number;
  min: number;
  max: number;
  outside: boolean;
  dragging: boolean;
}>();
</script>

<template>
  <span
    role="slider"
    tabindex="0"
    :data-part="part"
    :aria-label="part === 'start' ? 'From' : 'To'"
    :aria-valuetext="valueText"
    :aria-valuenow="value"
    :aria-valuemin="min"
    :aria-valuemax="max"
    aria-orientation="horizontal"
    class="group absolute inset-y-0 z-10 flex w-6 cursor-ew-resize justify-center pointer-coarse:w-11"
    :class="
      outside ? (part === 'start' ? '-translate-x-full' : 'translate-x-0') : '-translate-x-1/2'
    "
    :style="{ left: `${pct}%` }"
  >
    <span class="pointer-events-none absolute inset-y-0 w-0.5 bg-readout" />
    <span
      class="pointer-events-none absolute top-1/2 flex h-5 w-3 -translate-y-1/2 items-center justify-center gap-0.5 border border-line"
      :class="dragging ? 'bg-raised-hi' : 'bg-panel group-hover:bg-raised'"
    >
      <span class="h-3 w-px bg-text-3" />
      <span class="h-3 w-px bg-text-3" />
    </span>
    <span
      v-if="dragging"
      class="pointer-events-none absolute bottom-full mb-1 border border-line bg-raised px-1 font-mono text-2xs whitespace-nowrap text-readout"
      >{{ valueText.replace(/^(From|To) /, "") }}</span
    >
  </span>
</template>
