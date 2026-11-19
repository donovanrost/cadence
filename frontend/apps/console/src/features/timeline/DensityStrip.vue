<script setup lang="ts">
import { computed, ref } from "vue";
import { formatClock, plural, timeTicks } from "@/ui";
import type { Density } from "./api.ts";
import { brushRange, densityBars } from "./model.ts";

/**
 * E1 · Events per bucket, stacked by severity (shape is the bar; words are in the label), now-line.
 * E1 is a brush (OpsLists §Timeline): drag across it to narrow the window (`brush`); the window
 * picker above is the keyboard route to the same thing.
 */
const props = defineProps<{
  density: Density;
  window: { from: number; to: number };
  now: number;
}>();
const emit = defineEmits<{ brush: [range: { from: number; to: number }] }>();
/** Drag in progress, as fractions of the strip's width. */
const drag = ref<{ a: number; b: number } | null>(null);
const svg = ref<SVGSVGElement | null>(null);
const frac = (e: PointerEvent) => {
  const r = svg.value?.getBoundingClientRect();
  return r && r.width > 0 ? Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) : 0;
};
function down(e: PointerEvent) {
  if (e.button !== 0) return;
  svg.value?.setPointerCapture(e.pointerId);
  const f = frac(e);
  drag.value = { a: f, b: f };
}
function move(e: PointerEvent) {
  if (drag.value) drag.value = { ...drag.value, b: frac(e) };
}
function up() {
  const d = drag.value;
  drag.value = null;
  const range = d ? brushRange(props.window, d.a, d.b) : null;
  if (range) emit("brush", range);
}
const W = 1000;
const H = 48;
const view = computed(() => densityBars(props.density));
const x = (t: number) => ((t - props.window.from) / (props.window.to - props.window.from || 1)) * W;
const width = computed(
  () => (props.density.bucket_s * 1000 * W) / (props.window.to - props.window.from || 1),
);
/** Axis labels (ux Timeline review 5): round UTC ticks across the window. */
const ticks = computed(() =>
  timeTicks(props.window, 8).map((t) => ({
    t,
    left: `${(x(t) / W) * 100}%`,
    text: formatClock(new Date(t)).slice(0, 5),
  })),
);
const FILL = {
  critical: "fill-crit",
  caution: "fill-caution",
  nominal: "fill-nominal-dim",
  info: "fill-text-4",
} as const;
const label = computed(() => {
  const total = view.value.bars.reduce((n, b) => n + b.total, 0);
  const busiest = [...view.value.bars].sort((a, b) => b.total - a.total)[0];
  return `${plural(total, "event")} in the window${busiest && busiest.total ? `, busiest ${new Date(busiest.t).toISOString().slice(11, 16)}Z with ${busiest.total}` : ""}.`;
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <svg
      ref="svg"
      role="img"
      :aria-label="label"
      :viewBox="`0 0 ${W} ${H}`"
      preserveAspectRatio="none"
      class="block h-12 w-full cursor-crosshair touch-none border border-hairline bg-vacuum select-none"
      @pointerdown="down"
      @pointermove="move"
      @pointerup="up"
      @pointercancel="drag = null"
    >
      <template v-for="bar in view.bars" :key="bar.t">
        <rect
          v-for="s in bar.stack"
          :key="s.severity"
          :x="x(bar.t)"
          :width="Math.max(1, width - 1)"
          :y="H - s.to * (H - 4)"
          :height="(s.to - s.from) * (H - 4)"
          :class="FILL[s.severity]"
        />
      </template>
      <path :d="`M${x(now)} 0V${H}`" vector-effect="non-scaling-stroke" class="stroke-action" />
      <rect
        v-if="drag"
        :x="Math.min(drag.a, drag.b) * W"
        :width="Math.abs(drag.b - drag.a) * W"
        y="0"
        :height="H"
        class="fill-readout/15 stroke-readout"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    <div class="relative h-4" aria-hidden="true">
      <span
        v-for="tick in ticks"
        :key="tick.t"
        class="absolute -translate-x-1/2 font-mono text-[10px] whitespace-nowrap text-text-4"
        :style="{ left: tick.left }"
        >{{ tick.text }}</span
      >
    </div>
  </div>
</template>
