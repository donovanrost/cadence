<script setup lang="ts">
import { computed } from "vue";
import {
  envelopePath,
  linePath,
  scale,
  timeTicks,
  valueTicks,
  yDomain,
  type ComparisonSeries,
  type LimitSegment,
  type SeriesPoint,
  type TimeWindow,
} from "./scale.ts";

/**
 * Time series in a plot well (design-language §7 ApTimeSeries): min–max envelope + mean line,
 * dashed limit segments (they may change across the window) with a crit wash beyond red, and a
 * now-line. Plain-data props only, so it can move to @cadence/apogee-ui unchanged. The caller
 * passes the accessible sentence (`label`) and renders the legend as text in the slot.
 */
const props = withDefaults(
  defineProps<{
    series: readonly SeriesPoint[];
    comparison?: readonly ComparisonSeries[];
    limits?: readonly LimitSegment[];
    window: TimeWindow;
    now?: number | null;
    label: string;
    formatTick: (t: number) => string;
    formatValue: (v: number) => string;
    height?: number;
    /** Bucket width of the series; consecutive points further apart than 1.5× are a gap. */
    stepMs?: number | null;
  }>(),
  { comparison: () => [], limits: () => [], now: null, height: 250, stepMs: null },
);

const W = 1000;
const domain = computed(() =>
  yDomain([props.series, ...props.comparison.map((c) => c.points)], props.limits),
);
const x = computed(() => scale(props.window.from, props.window.to, 0, W));
const y = computed(() => scale(domain.value[0], domain.value[1], props.height, 0));

const clampX = (t: number) => Math.min(W, Math.max(0, x.value(t)));
const pct = (n: number, of: number) => `${(n / of) * 100}%`;

const mean = computed(() => linePath(props.series, x.value, y.value, props.stepMs));
const envelope = computed(() => envelopePath(props.series, x.value, y.value, props.stepMs));
const STROKE = {
  readout: "stroke-readout",
  "text-2": "stroke-text-2",
  "text-3": "stroke-text-3",
  "text-4": "stroke-text-4",
} as const;
const DASH = { solid: undefined, dashed: "8 5", dotted: "2 4" } as const;
const others = computed(() =>
  props.comparison.map((c) => ({
    d: linePath(c.points, x.value, y.value, props.stepMs),
    stroke: STROKE[c.tone],
    dash: DASH[c.dash],
  })),
);

const limitLines = computed(() =>
  props.limits.map((l, i) => {
    const x0 = clampX(l.from);
    const x1 = clampX(l.to);
    const ly = y.value(l.value);
    const wash =
      l.kind === "crit"
        ? {
            x: x0,
            w: x1 - x0,
            y: l.side === "low" ? ly : 0,
            h: l.side === "low" ? props.height - ly : ly,
          }
        : null;
    return { key: i, d: `M${x0} ${ly}H${x1}`, kind: l.kind, wash };
  }),
);

const yTicks = computed(() =>
  valueTicks(domain.value).map((v) => ({
    v,
    top: pct(y.value(v), props.height),
    text: props.formatValue(v),
  })),
);
const xTicks = computed(() =>
  timeTicks(props.window).map((t) => ({ t, left: pct(x.value(t), W), text: props.formatTick(t) })),
);
const nowX = computed(() =>
  props.now !== null && props.now >= props.window.from && props.now <= props.window.to
    ? x.value(props.now)
    : null,
);
</script>

<template>
  <figure class="m-0 flex flex-col gap-1.5">
    <div class="grid grid-cols-[44px_minmax(0,1fr)] gap-x-2">
      <div class="relative" aria-hidden="true">
        <span
          v-for="tick in yTicks"
          :key="tick.v"
          class="absolute right-0 -translate-y-1/2 font-mono text-[10px] text-text-4 tabular"
          :style="{ top: tick.top }"
          >{{ tick.text }}</span
        >
      </div>
      <svg
        role="img"
        :aria-label="label"
        :viewBox="`0 0 ${W} ${height}`"
        preserveAspectRatio="none"
        class="block w-full border border-hairline-faint bg-vacuum"
        :style="{ height: `${height}px` }"
      >
        <g class="stroke-hairline-faint" vector-effect="non-scaling-stroke">
          <path
            v-for="tick in yTicks"
            :key="tick.v"
            :d="`M0 ${y(tick.v)}H${W}`"
            vector-effect="non-scaling-stroke"
          />
        </g>
        <template v-for="line in limitLines" :key="line.key">
          <rect
            v-if="line.wash"
            v-bind="{ x: line.wash.x, y: line.wash.y, width: line.wash.w, height: line.wash.h }"
            class="fill-crit/8"
          />
          <path
            :d="line.d"
            fill="none"
            stroke-dasharray="6 4"
            vector-effect="non-scaling-stroke"
            :class="line.kind === 'crit' ? 'stroke-crit' : 'stroke-caution'"
          />
        </template>
        <path
          v-for="(line, i) in others"
          :key="i"
          :d="line.d"
          fill="none"
          stroke-width="1.4"
          :stroke-dasharray="line.dash"
          vector-effect="non-scaling-stroke"
          :class="line.stroke"
        />
        <path :d="envelope" class="fill-readout/12" />
        <path
          :d="mean"
          fill="none"
          stroke-width="1.8"
          vector-effect="non-scaling-stroke"
          class="stroke-readout"
        />
        <path
          v-if="nowX !== null"
          :d="`M${nowX} 0V${height}`"
          vector-effect="non-scaling-stroke"
          class="stroke-action"
        />
      </svg>
      <div />
      <div class="relative h-4" aria-hidden="true">
        <span
          v-for="tick in xTicks"
          :key="tick.t"
          class="absolute -translate-x-1/2 font-mono text-[10px] whitespace-nowrap text-text-4"
          :style="{ left: tick.left }"
          >{{ tick.text }}</span
        >
      </div>
    </div>
    <figcaption v-if="$slots.default" class="pl-[52px] font-mono text-xs text-text-3">
      <slot />
    </figcaption>
  </figure>
</template>
