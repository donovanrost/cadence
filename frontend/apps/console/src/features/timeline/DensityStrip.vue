<script setup lang="ts">
import { computed } from "vue";
import { formatClock, plural, timeTicks } from "@/ui";
import type { Density } from "./api.ts";
import { densityBars } from "./model.ts";

/** E1 · Events per bucket, stacked by severity (shape is the bar; words are in the label), now-line. */
const props = defineProps<{
  density: Density;
  window: { from: number; to: number };
  now: number;
}>();
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
      role="img"
      :aria-label="label"
      :viewBox="`0 0 ${W} ${H}`"
      preserveAspectRatio="none"
      class="block h-12 w-full border border-hairline bg-vacuum"
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
