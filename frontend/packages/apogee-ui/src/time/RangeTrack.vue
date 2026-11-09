<script setup lang="ts">
import { computed, ref } from "vue";
import type { TimeRange, TrackBand } from "./types.ts";

/**
 * Context track (default 24h ending now) with umbra / pass / alarm bands and the selected window.
 * Drag across it to pick a window; the From/To fields are the keyboard path.
 */
const props = defineProps<{
  span: TimeRange;
  bands: readonly TrackBand[];
  selected: TimeRange;
  label: string;
}>();
const emit = defineEmits<{ select: [range: TimeRange] }>();

const track = ref<HTMLElement | null>(null);
const drag = ref<{ anchor: number; current: number } | null>(null);
const width = computed(() => props.span.to - props.span.from);
const pct = (t: number) => Math.max(0, Math.min(100, ((t - props.span.from) / width.value) * 100));
const box = (r: TimeRange) => ({
  left: `${pct(r.from)}%`,
  width: `${Math.max(0.4, pct(r.to) - pct(r.from))}%`,
});
const shown = computed<TimeRange>(() =>
  drag.value
    ? {
        from: Math.min(drag.value.anchor, drag.value.current),
        to: Math.max(drag.value.anchor, drag.value.current),
      }
    : props.selected,
);
const ticks = computed(() =>
  [0, 0.25, 0.5, 0.75, 1].map((f) => ({
    f,
    hours: Math.round(((1 - f) * width.value) / 3_600_000),
  })),
);

function timeAt(clientX: number): number {
  const rect = track.value?.getBoundingClientRect();
  if (!rect || rect.width === 0) return props.span.from;
  const f = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
  return Math.round(props.span.from + f * width.value);
}
function down(event: PointerEvent) {
  const t = timeAt(event.clientX);
  drag.value = { anchor: t, current: t };
  (event.currentTarget as HTMLElement | null)?.setPointerCapture(event.pointerId);
}
function move(event: PointerEvent) {
  if (drag.value) drag.value = { ...drag.value, current: timeAt(event.clientX) };
}
function up() {
  const r = shown.value;
  drag.value = null;
  if (r.to - r.from >= 60_000) emit("select", r);
}
</script>

<template>
  <div class="flex flex-col gap-1">
    <div
      ref="track"
      role="img"
      :aria-label="label"
      class="relative h-9 cursor-crosshair touch-none border border-hairline-faint bg-well select-none"
      @pointerdown="down"
      @pointermove="move"
      @pointerup="up"
      @pointercancel="drag = null"
    >
      <span
        v-for="(band, i) in bands"
        :key="i"
        class="absolute"
        :class="{
          'inset-y-0 bg-viz-umbra': band.kind === 'umbra',
          'top-1/2 h-2 -translate-y-1/2 bg-text-3': band.kind === 'pass',
          'inset-y-0 w-px bg-crit': band.kind === 'alarm',
        }"
        :style="band.kind === 'alarm' ? { left: `${pct(band.from)}%` } : box(band)"
      />
      <span
        class="absolute inset-y-0 border-x-2 border-readout bg-[var(--apogee-wash-scheduled)]"
        :style="box(shown)"
      />
    </div>
    <div class="flex justify-between font-mono text-2xs text-text-4 uppercase">
      <span v-for="tick in ticks" :key="tick.f">{{
        tick.hours === 0 ? "Now" : `−${tick.hours}h`
      }}</span>
    </div>
  </div>
</template>
