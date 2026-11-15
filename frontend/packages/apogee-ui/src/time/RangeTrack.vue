<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { formatShort } from "../lib/format.ts";
import RangeHandle from "./RangeHandle.vue";
import { dragged, keyStep, keyed, MIN_RANGE, rangeText, type DragPart } from "./range-drag.ts";
import type { TimeRange, TrackBand } from "./types.ts";

/**
 * Context track (default 24h ending now) with umbra / pass / alarm bands and the selected window
 * (ux U62). Drag a handle to move one end, the band to move the window, empty track for a new
 * one; From/To follow live (`preview`), release commits (`select`), Esc restores. The handles
 * and the band are sliders too. A click that moves under 4px does nothing.
 */
const props = defineProps<{
  span: TimeRange;
  bands: readonly TrackBand[];
  selected: TimeRange;
  label: string;
  /** For the tick labels: hours from now ('−6h', 'Now', '+12h'). */
  now: number;
}>();
const emit = defineEmits<{ select: [range: TimeRange]; preview: [range: TimeRange | null] }>();

const track = ref<HTMLElement | null>(null);
const trackPx = ref(0);
let observer: ResizeObserver | null = null;
onMounted(() => {
  if (!track.value || typeof ResizeObserver === "undefined") return;
  observer = new ResizeObserver(([e]) => (trackPx.value = e?.contentRect.width ?? 0));
  observer.observe(track.value);
});
onBeforeUnmount(() => {
  observer?.disconnect();
  stopEsc();
});

type Drag = { part: DragPart; base: TimeRange; grab: number; x0: number; moved: boolean };
const drag = ref<Drag | null>(null);
const draft = ref<TimeRange | null>(null);
const announce = ref("");
const width = computed(() => props.span.to - props.span.from);
const pct = (t: number) => Math.max(0, Math.min(100, ((t - props.span.from) / width.value) * 100));
const box = (r: TimeRange) => ({
  left: `${pct(r.from)}%`,
  width: `${Math.max(0.4, pct(r.to) - pct(r.from))}%`,
});
const shown = computed<TimeRange>(() => draft.value ?? props.selected);
/** Below 16px of band the handles sit outside its ends (ux). */
const outside = computed(
  () => ((pct(shown.value.to) - pct(shown.value.from)) / 100) * trackPx.value < 16,
);
const ticks = computed(() =>
  [0, 0.25, 0.5, 0.75, 1].map((f) => {
    const hours = Math.round((props.span.from + f * width.value - props.now) / 3_600_000);
    return { f, text: hours === 0 ? "Now" : hours < 0 ? `−${-hours}h` : `+${hours}h` };
  }),
);
const valueText = (part: "start" | "end") =>
  `${part === "start" ? "From" : "To"} ${formatShort(new Date(part === "start" ? shown.value.from : shown.value.to))}`;

function timeAt(clientX: number): number {
  const rect = track.value?.getBoundingClientRect();
  if (!rect || rect.width === 0) return props.span.from;
  const f = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
  return props.span.from + f * width.value;
}
function partOf(target: EventTarget | null): DragPart {
  const part =
    target instanceof Element ? target.closest("[data-part]")?.getAttribute("data-part") : null;
  return part === "start" || part === "end" || part === "band" ? part : "new";
}
function down(event: PointerEvent) {
  if (event.button !== 0) return;
  drag.value = {
    part: partOf(event.target),
    base: props.selected,
    grab: timeAt(event.clientX),
    x0: event.clientX,
    moved: false,
  };
  if (event.currentTarget instanceof HTMLElement)
    event.currentTarget.setPointerCapture(event.pointerId);
  // Capture: a drag's Esc must reach us before an enclosing ApSheet's dialog closes on it.
  window.addEventListener("keydown", onEsc, true);
}
function move(event: PointerEvent) {
  const d = drag.value;
  if (!d || (!d.moved && Math.abs(event.clientX - d.x0) < 4)) return;
  d.moved = true;
  draft.value = dragged(d.part, d.base, d.grab, timeAt(event.clientX), props.span);
  emit("preview", draft.value);
}
function up() {
  const d = drag.value;
  const r = draft.value;
  end();
  if (d?.moved && r && r.to - r.from >= MIN_RANGE) commit(r);
}
function end() {
  const previewing = draft.value !== null;
  drag.value = null;
  draft.value = null;
  stopEsc();
  if (previewing) emit("preview", null);
}
/** Esc mid-drag cancels only the drag; with no drag it passes on (and closes the sheet). */
function onEsc(event: KeyboardEvent) {
  if (event.key !== "Escape" || !drag.value) return;
  event.preventDefault();
  event.stopPropagation();
  end();
}
function stopEsc() {
  window.removeEventListener("keydown", onEsc, true);
}
function commit(r: TimeRange) {
  emit("select", r);
  announce.value = rangeText(r);
}
function key(part: "start" | "end" | "band", event: KeyboardEvent) {
  const big = event.shiftKey || event.key === "PageUp" || event.key === "PageDown";
  const r = keyed(part, event.key, props.selected, props.span, keyStep(props.span, big));
  if (!r) return;
  event.preventDefault();
  commit(r);
}
</script>

<template>
  <div class="flex flex-col gap-1">
    <div
      ref="track"
      role="group"
      :aria-label="label"
      class="relative h-9 cursor-crosshair touch-none border border-hairline-faint bg-well select-none"
      @pointerdown="down"
      @pointermove="move"
      @pointerup="up"
      @pointercancel="end"
    >
      <span
        v-for="(band, i) in bands"
        :key="i"
        class="pointer-events-none absolute"
        :class="{
          'inset-y-0 bg-viz-umbra': band.kind === 'umbra',
          'top-1/2 h-2 -translate-y-1/2 bg-text-3': band.kind === 'pass',
          'inset-y-0 w-px bg-crit': band.kind === 'alarm',
        }"
        :style="band.kind === 'alarm' ? { left: `${pct(band.from)}%` } : box(band)"
      />
      <span
        role="slider"
        tabindex="0"
        data-part="band"
        aria-label="Range"
        :aria-valuetext="rangeText(shown)"
        :aria-valuenow="shown.from"
        :aria-valuemin="span.from"
        :aria-valuemax="span.to"
        class="absolute inset-y-0 bg-[var(--apogee-wash-scheduled)]"
        :class="drag?.part === 'band' ? 'cursor-grabbing' : 'cursor-grab'"
        :style="box(shown)"
        @keydown="key('band', $event)"
      />
      <RangeHandle
        v-for="part in ['start', 'end'] as const"
        :key="part"
        :part="part"
        :pct="pct(part === 'start' ? shown.from : shown.to)"
        :value-text="valueText(part)"
        :value="part === 'start' ? shown.from : shown.to"
        :min="span.from"
        :max="span.to"
        :outside="outside"
        :dragging="drag?.moved === true && drag.part === part"
        @keydown="key(part, $event)"
      />
    </div>
    <div class="flex justify-between font-mono text-2xs text-text-4 uppercase">
      <span v-for="tick in ticks" :key="tick.f">{{ tick.text }}</span>
    </div>
    <span class="sr-only" aria-live="polite">{{ announce }}</span>
  </div>
</template>
