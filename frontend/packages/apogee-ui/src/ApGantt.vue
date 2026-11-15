<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import {
  extent,
  hourTicks,
  neighbour,
  position,
  type GanttBand,
  type GanttBar,
  type GanttRow,
  type GanttWindow,
} from "./gantt/model.ts";
import { formatClock } from "./lib/format.ts";
import ApStatusMark from "./ApStatusMark.vue";

/**
 * Stations × time (design-language ApPassStrip/ApGantt). Bars are buttons with one roving tab stop:
 * arrows move between bars (by time in a row, nearest in time across rows), Enter selects.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    rows: readonly GanttRow[];
    bars: readonly GanttBar[];
    window: GanttWindow;
    bands?: readonly GanttBand[] | undefined;
    now?: number | null | undefined;
    selected?: string | null | undefined;
    laneHeight?: number | undefined;
    /** Row label column width in px (long provider station refs need more than the default). */
    labelWidth?: number | undefined;
  }>(),
  { bands: () => [], now: null, selected: null, laneHeight: 30, labelWidth: 88 },
);
const emit = defineEmits<{ select: [id: string] }>();

const root = ref<HTMLElement | null>(null);
/** Track width in px (lanes minus the label column), for deciding which labels fit. */
const trackWidth = ref(0);
let observer: ResizeObserver | null = null;
onMounted(() => {
  if (!root.value || typeof ResizeObserver === "undefined") return;
  observer = new ResizeObserver(([entry]) => {
    trackWidth.value = Math.max(0, (entry?.contentRect.width ?? 0) - props.labelWidth);
  });
  observer.observe(root.value);
});
onBeforeUnmount(() => observer?.disconnect());
/** Mono 10px ≈ 6.1px per glyph + 8px padding. Labels that don't fit stay in the tooltip / name only. */
const labelFits = (bar: GanttBar) => {
  if (!bar.label) return false;
  const e = extent(props.window, bar.from, bar.to);
  return (e.width / 100) * trackWidth.value >= bar.label.length * 6.1 + 8;
};
const focusId = ref<string | null>(null);
const tabStop = computed(() => focusId.value ?? props.selected ?? props.bars[0]?.id ?? null);
const byRow = computed(() => {
  const map = new Map<string, GanttBar[]>();
  for (const bar of props.bars) {
    const row = map.get(bar.rowId);
    if (row) row.push(bar);
    else map.set(bar.rowId, [bar]);
  }
  return map;
});
const bandsFor = (rowId: string) =>
  props.bands.filter((b) => b.rowId === null || b.rowId === rowId);
const ticks = computed(() => hourTicks(props.window));
const nowPct = computed(() =>
  props.now !== null && props.now >= props.window.from && props.now <= props.window.to
    ? position(props.window, props.now)
    : null,
);
const style = (from: number, to: number) => {
  const e = extent(props.window, from, to);
  return { left: `${e.left}%`, width: `${e.width}%` };
};

async function onKey(event: KeyboardEvent, id: string) {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    emit("select", id);
    return;
  }
  if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) return;
  event.preventDefault();
  const next = neighbour(props.rows, props.bars, id, event.key as "ArrowLeft");
  if (next === null) return;
  focusId.value = next;
  await nextTick();
  root.value?.querySelector<HTMLElement>(`[data-bar="${CSS.escape(next)}"]`)?.focus();
}
const BAND_WORDS: Readonly<Record<GanttBand["kind"], string>> = {
  outage: "Outage",
  maintenance: "Maintenance",
  degraded: "Degraded",
  unusable: "Unusable",
};
/** Legend for the band kinds on screen (ux K1 #11): swatch + word, never colour alone. */
const bandKinds = computed(() =>
  (["outage", "maintenance", "degraded", "unusable"] as const).filter((k) =>
    props.bands.some((b) => b.kind === k),
  ),
);
/** Bar kinds whose look needs a word (U30): legended only when on screen. */
const BAR_WORDS = { unconfirmed: "Unconfirmed" } as const;
const barKinds = computed(() =>
  (["unconfirmed"] as const).filter((k) => props.bars.some((b) => b.kind === k)),
);
/** Attention marks (ux U45): legended only while one is on screen, fixed words. */
const MARK_WORDS = { caution: "Needs attention", crit: "Missed" } as const;
const markStates = computed(() =>
  (["caution", "crit"] as const).filter((k) => props.bars.some((b) => b.attention === k)),
);
</script>

<template>
  <div ref="root" role="group" :aria-label="label" class="flex min-w-0 flex-col">
    <ul
      v-if="bandKinds.length > 0 || barKinds.length > 0 || markStates.length > 0"
      class="m-0 mb-2 flex list-none flex-wrap gap-x-4 gap-y-1 p-0 font-mono text-xs text-text-3 uppercase"
    >
      <li v-for="k in bandKinds" :key="k" class="flex items-center gap-1.5">
        <span
          aria-hidden="true"
          class="ap-band relative inline-block h-3 w-5 border border-hairline"
          :class="`ap-band--${k}`"
        />{{ BAND_WORDS[k] }}
      </li>
      <li v-for="k in barKinds" :key="k" class="flex items-center gap-1.5">
        <span aria-hidden="true" class="relative inline-block h-3 w-5" :class="`ap-bar--${k}`" />{{
          BAR_WORDS[k]
        }}
      </li>
      <li v-for="k in markStates" :key="`mark-${k}`" class="flex items-center gap-1.5">
        <ApStatusMark :state="k" />{{ MARK_WORDS[k] }}
      </li>
    </ul>
    <div class="relative flex flex-col gap-px">
      <div
        v-for="row in rows"
        :key="row.id"
        role="group"
        :aria-label="row.name ?? row.label"
        class="flex items-stretch"
      >
        <div
          class="flex flex-none items-center gap-1.5 pr-2 font-mono text-xs"
          :style="{ width: `${labelWidth}px` }"
          :class="row.degraded ? 'text-caution-text' : 'text-text-2'"
        >
          <span class="truncate" :title="row.name ?? row.label">{{ row.label }}</span>
          <span v-if="row.tag" class="text-2xs text-text-4">{{ row.tag }}</span>
        </div>
        <div
          class="relative flex-1 border border-hairline-faint bg-well"
          :style="{ height: `${laneHeight}px` }"
        >
          <span
            v-for="(band, i) in bandsFor(row.id)"
            :key="`b${i}`"
            class="ap-band absolute inset-y-0"
            :class="`ap-band--${band.kind}`"
            :style="style(band.from, band.to)"
            :title="band.label"
          />
          <template v-for="bar in byRow.get(row.id) ?? []" :key="bar.id">
            <button
              type="button"
              :data-bar="bar.id"
              :tabindex="bar.id === tabStop ? 0 : -1"
              :aria-label="bar.description"
              :aria-pressed="bar.id === selected"
              :title="bar.description"
              class="ap-bar absolute top-1/2 h-4 -translate-y-1/2 overflow-hidden px-1 text-left font-mono text-2xs leading-4 whitespace-nowrap"
              :class="[
                `ap-bar--${bar.kind}`,
                bar.id === selected ? 'ap-bar--selected' : '',
                bar.dim ? 'ap-bar--dim' : '',
                bar.notch ? 'ap-bar--notch' : '',
                bar.attention && labelFits(bar) ? 'pl-2.5' : '',
              ]"
              :style="style(bar.from, bar.to)"
              @click="emit('select', bar.id)"
              @focus="focusId = bar.id"
              @keydown="onKey($event, bar.id)"
            >
              <!-- A hatched bar's label sits on a clean base, not the stripes (qa U30 #4). -->
              <span
                v-if="labelFits(bar)"
                aria-hidden="true"
                :class="bar.kind === 'unconfirmed' ? 'bg-[var(--color-stale-deep)]' : ''"
                >{{ bar.label }}</span
              >
            </button>
            <!-- U45: the mark sits on the bar's leading edge, outside the bar's clip, so it stays whole
               on a pass a few px wide; it follows the bar's dim. -->
            <span
              v-if="bar.attention"
              :data-bar-mark="bar.id"
              class="pointer-events-none absolute top-1/2 z-10 flex -translate-x-1/2 -translate-y-1/2"
              :class="bar.dim ? 'opacity-35' : ''"
              :style="{ left: style(bar.from, bar.to).left }"
              ><ApStatusMark :state="bar.attention"
            /></span>
          </template>
        </div>
      </div>
      <div
        v-if="nowPct !== null"
        aria-hidden="true"
        class="pointer-events-none absolute -inset-y-1 right-0"
        :style="{ left: `${labelWidth}px` }"
      >
        <span class="absolute inset-y-0 w-px bg-readout" :style="{ left: `${nowPct}%` }" />
      </div>
    </div>
    <div
      aria-hidden="true"
      class="relative mt-1 h-4 font-mono text-2xs text-text-4"
      :style="{ marginLeft: `${labelWidth}px` }"
    >
      <template v-for="tick in ticks" :key="tick.t">
        <span
          class="absolute top-0 w-px"
          :class="tick.major ? 'h-1.5 bg-line-strong' : 'h-1 bg-hairline'"
          :style="{ left: `${position(window, tick.t)}%` }"
        />
        <span
          v-if="tick.major"
          class="absolute top-1.5 -translate-x-1/2"
          :style="{ left: `${position(window, tick.t)}%` }"
          >{{ formatClock(new Date(tick.t)).slice(0, 5) }}Z</span
        >
      </template>
    </div>
  </div>
</template>

<style scoped>
.ap-bar {
  min-width: 5px;
  border: 0;
  padding-block: 0;
  cursor: pointer;
  box-sizing: border-box;
  background: transparent;
  color: var(--color-on-action);
}
.ap-bar--own,
.ap-bar--focused,
.ap-bar--live,
.ap-bar--new {
  background: var(--color-readout);
}
.ap-bar--live {
  font-weight: 600;
}
.ap-bar--focused {
  box-shadow:
    0 0 0 2px var(--color-vacuum),
    0 0 0 3px var(--color-readout);
}
.ap-bar--new {
  box-shadow:
    0 0 0 2px var(--color-vacuum),
    0 0 0 3px var(--color-nominal-text);
}
.ap-bar--window {
  border: 1px dashed var(--color-readout);
  background: rgba(230, 237, 243, 0.06);
  color: var(--color-text-2);
}
.ap-bar--clash {
  border: 1px dashed var(--color-caution);
  background: var(--apogee-wash-caution);
  color: var(--color-caution-text);
}
.ap-bar--problem {
  background: var(--color-caution);
}
.ap-bar--scheduled {
  border: 1px solid var(--color-line-strong);
  background: var(--apogee-wash-scheduled);
  color: var(--color-text-2);
}
.ap-bar--risk {
  background: var(--color-readout);
  box-shadow:
    0 0 0 2px var(--color-vacuum),
    0 0 0 3px var(--color-caution);
}
.ap-bar--done {
  border: 1px solid var(--color-line);
  background: transparent;
  /* U27: dim the mark, not the text (labels stay ≥ text-3). */
  color: var(--color-text-3);
}
.ap-bar--unconfirmed {
  /* U30: unknown truth reads stale; label on the deep base keeps its contrast (U27). */
  border: 1px solid var(--color-stale);
  background-color: var(--color-stale-deep);
  background-image: var(--apogee-hatch-stale-cell);
  color: var(--color-stale-text);
}
.ap-bar--dim {
  /* Faint, not hidden: still a tab stop with its description (Contacts `sc any`). */
  opacity: 0.35;
}
.ap-bar--notch::before {
  /* Queued uplink on this pass (Contacts `.cb.up`): an inset dark notch, kind's own look kept. */
  content: "";
  position: absolute;
  top: 0;
  left: 50%;
  width: 6px;
  height: 4px;
  transform: translateX(-50%);
  background: var(--color-vacuum);
}
.ap-bar--selected {
  outline: 2px solid var(--color-readout);
  outline-offset: 3px;
}
.ap-band--outage {
  background-image: var(--apogee-hatch-outage);
}
.ap-band--maintenance {
  background-image: var(--apogee-hatch-maint);
}
.ap-band--degraded {
  background: var(--apogee-wash-caution);
  border-top: 1px dashed var(--color-caution);
}
.ap-band--unusable {
  background-image: var(--apogee-hatch-unusable);
}
</style>
