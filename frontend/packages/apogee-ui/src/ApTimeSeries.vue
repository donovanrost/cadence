<script setup lang="ts">
import { computed, ref } from "vue";
import {
  envelopePath,
  linePath,
  pointAt,
  scale,
  timeTicks,
  valueTicks,
  yDomain,
  type ComparisonSeries,
  type LimitSegment,
  type SeriesPoint,
  type TimeBand,
  type TimeMark,
  type TimeWindow,
} from "./time-series.ts";

/**
 * Time series in a plot well (design-language §7 ApTimeSeries): min–max envelope + mean line,
 * dashed limit segments (they may change across the window) with a crit wash beyond red, and a
 * now-line. Plain-data props only. The caller
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
    /** Labelled spans behind the plot: passes (AOS–LOS + station), outages. */
    bands?: readonly TimeBand[];
    /** Marked moments: a ring on the series (plus a dashed vertical), read out by label. */
    marks?: readonly TimeMark[];
    /** The main series' name in the hover readout. */
    seriesName?: string | undefined;
    /** Readout time; defaults to `formatTick`. */
    formatTime?: ((t: number) => string) | undefined;
  }>(),
  {
    comparison: () => [],
    limits: () => [],
    now: null,
    height: 250,
    stepMs: null,
    bands: () => [],
    marks: () => [],
    seriesName: undefined,
    formatTime: undefined,
  },
);
/**
 * Crosshair time. Bind one ref across a stack of small multiples (`v-model:hover`) and they
 * share the crosshair; each chart reads its own series at that time.
 */
const hover = defineModel<number | null>("hover", { default: null });

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
const bandBoxes = computed(() =>
  props.bands.map((b, i) => {
    const x0 = clampX(b.from);
    const x1 = clampX(b.to);
    const cls =
      b.kind === "pass"
        ? "border-x border-hairline bg-readout/5"
        : b.kind === "episode"
          ? b.severity === "crit"
            ? "border-x border-crit/40 bg-[var(--apogee-wash-crit)]"
            : "border-x border-caution/40 bg-[var(--apogee-wash-caution)]"
          : "";
    return { key: i, kind: b.kind, cls, label: b.label, left: pct(x0, W), width: pct(x1 - x0, W) };
  }),
);

const plot = ref<HTMLElement | null>(null);
function onMove(event: PointerEvent) {
  const box = plot.value?.getBoundingClientRect();
  if (!box || box.width === 0) return;
  const f = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width));
  hover.value = props.window.from + f * (props.window.to - props.window.from);
}
/** Half a bucket either side (or 1/200 of the window): never read a value inside a gap. */
const tolerance = computed(() =>
  props.stepMs ? props.stepMs * 0.75 : (props.window.to - props.window.from) / 200,
);
const crosshair = computed(() => {
  const t = hover.value;
  if (t === null || t < props.window.from || t > props.window.to) return null;
  const at = (points: readonly SeriesPoint[]) => pointAt(points, t, tolerance.value);
  const rows = [
    { name: props.seriesName ?? "Value", p: at(props.series) },
    ...props.comparison.map((c, i) => ({ name: c.name ?? `Series ${i + 2}`, p: at(c.points) })),
  ].map((r) => ({ name: r.name, text: r.p ? props.formatValue(r.p.mean) : "no data" }));
  const f = (t - props.window.from) / (props.window.to - props.window.from || 1);
  return {
    left: `${f * 100}%`,
    flip: f > 0.6,
    time: (props.formatTime ?? props.formatTick)(t),
    rows,
  };
});

/** Ringed when the marked series has a value at `t`; the dashed vertical always. */
const markBoxes = computed(() =>
  props.marks
    .filter((m) => m.t >= props.window.from && m.t <= props.window.to)
    .map((m, i) => {
      const points =
        m.series === undefined
          ? props.series
          : (props.comparison.find((c) => c.name === m.series)?.points ?? []);
      const p = pointAt(points, m.t, tolerance.value);
      return {
        key: i,
        label: m.label,
        left: pct(x.value(m.t), W),
        top: p ? pct(y.value(p.mean), props.height) : null,
      };
    }),
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
      <div
        ref="plot"
        class="relative border border-hairline-faint bg-vacuum"
        @pointermove="onMove"
        @pointerleave="hover = null"
      >
        <!-- Bands behind the transparent plot; labels on a solid base, never on a hatch (§7). -->
        <div
          v-for="band in bandBoxes"
          :key="band.key"
          aria-hidden="true"
          class="pointer-events-none absolute inset-y-0"
          :class="band.cls"
          :style="{
            left: band.left,
            width: band.width,
            backgroundImage: band.kind === 'outage' ? 'var(--apogee-hatch-outage)' : undefined,
          }"
        >
          <span
            v-if="band.label"
            class="absolute top-0 left-0 bg-vacuum px-1 font-mono text-[10px] whitespace-nowrap text-text-3"
            >{{ band.label }}</span
          >
        </div>
        <svg
          role="img"
          :aria-label="label"
          :viewBox="`0 0 ${W} ${height}`"
          preserveAspectRatio="none"
          class="relative block w-full"
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
        <!-- Marks: a dashed vertical and a ring (shape, not colour alone); the label is read out. -->
        <template v-for="m in markBoxes" :key="m.key">
          <span
            aria-hidden="true"
            class="pointer-events-none absolute inset-y-0 w-0 border-l border-dashed border-readout"
            :style="{ left: m.left }"
          />
          <span
            v-if="m.top !== null"
            aria-hidden="true"
            class="pointer-events-none absolute size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-readout"
            :style="{ left: m.left, top: m.top }"
          />
        </template>
        <template v-if="crosshair">
          <span
            aria-hidden="true"
            class="pointer-events-none absolute inset-y-0 w-px bg-text-3"
            :style="{ left: crosshair.left }"
          />
          <!-- Supplementary to the accessible sentence: a sighted reading of every series. -->
          <div
            aria-hidden="true"
            class="pointer-events-none absolute top-1 z-10 flex flex-col gap-0.5 border border-line bg-raised px-2 py-1 font-mono text-[11px] whitespace-nowrap text-readout tabular"
            :class="crosshair.flip ? '-translate-x-[calc(100%+6px)]' : 'translate-x-[6px]'"
            :style="{ left: crosshair.left }"
          >
            <span class="text-text-3">{{ crosshair.time }}</span>
            <span v-for="row in crosshair.rows" :key="row.name"
              >{{ row.name }} <span class="text-text-2">{{ row.text }}</span></span
            >
          </div>
        </template>
      </div>
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
    <p v-if="markBoxes.length" class="sr-only">
      Marked: {{ markBoxes.map((m) => m.label).join("; ") }}.
    </p>
    <figcaption v-if="$slots.default" class="pl-[52px] font-mono text-xs text-text-3">
      <slot />
    </figcaption>
  </figure>
</template>
