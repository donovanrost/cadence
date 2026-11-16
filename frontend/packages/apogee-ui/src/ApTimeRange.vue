<script setup lang="ts">
import { computed, ref, watch } from "vue";
import ApSegmented from "./ApSegmented.vue";
import { useNow } from "./lib/clock.ts";
import { formatAbsolute } from "./lib/format.ts";
import RangeTrack from "./time/RangeTrack.vue";
import { parseTime } from "./time/parse.ts";
import type { RangePreset, TimeRange, TrackBand } from "./time/types.ts";

/**
 * Time window for plots and timelines (board TimePicker B). Presets come from the caller and
 * should already snap to orbits/passes. From/To accept typed times; the track shows context
 * bands and supports drag-to-select.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    presets: readonly RangePreset[];
    bands?: readonly TrackBand[] | undefined;
    /** Track span; defaults to the 24 h ending now. */
    span?: TimeRange | undefined;
  }>(),
  { bands: () => [] },
);
const model = defineModel<TimeRange>({ required: true });
const now = useNow();

const presetId = ref<string>("custom");
const options = computed(() => [
  ...props.presets.map((p) => ({ value: p.id, label: p.label })),
  ...(presetId.value === "custom" ? [{ value: "custom", label: "Custom" }] : []),
]);
const span = computed<TimeRange>(
  () => props.span ?? { from: now.value.getTime() - 86_400_000, to: now.value.getTime() },
);
const fromText = ref("");
const toText = ref("");
/** A drag in progress on the track: the fields follow it until release or Esc (ux U62). */
const previewing = ref(false);
function showRange(r: TimeRange) {
  fromText.value = formatAbsolute(new Date(r.from));
  toText.value = formatAbsolute(new Date(r.to));
}
function onPreview(r: TimeRange | null) {
  previewing.value = r !== null;
  showRange(r ?? model.value);
}
const trackHours = computed(() => Math.round((span.value.to - span.value.from) / 3_600_000));
watch(
  model,
  (r) => {
    showRange(r);
    // Presets that track "now" drift by seconds between renders; match within a minute.
    presetId.value =
      props.presets.find(
        (p) => Math.abs(p.from - r.from) <= 60_000 && Math.abs(p.to - r.to) <= 60_000,
      )?.id ?? "custom";
  },
  { immediate: true },
);
const fromBad = computed(() => parseTime(fromText.value, now.value.getTime()) === null);
const toBad = computed(() => parseTime(toText.value, now.value.getTime()) === null);
const order = computed(() => {
  const f = parseTime(fromText.value, now.value.getTime());
  const t = parseTime(toText.value, now.value.getTime());
  return f !== null && t !== null && f >= t;
});

function choose(id: string) {
  const preset = props.presets.find((p) => p.id === id);
  if (preset) model.value = { from: preset.from, to: preset.to };
}
function commitFields() {
  const f = parseTime(fromText.value, now.value.getTime());
  const t = parseTime(toText.value, now.value.getTime());
  if (f !== null && t !== null && f < t) model.value = { from: f, to: t };
}
const fieldClass = (bad: boolean) => [
  "h-9 w-full border bg-well px-3 font-mono text-md outline-none focus:border-readout",
  previewing.value
    ? "border-readout text-text-2"
    : bad
      ? "border-caution text-readout"
      : "border-line text-readout",
];
</script>

<template>
  <fieldset class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
    <legend class="ap-label mb-1.5">{{ label }}</legend>
    <ApSegmented
      class="self-start"
      :model-value="presetId"
      :options="options"
      :label="`${label} presets`"
      @update:model-value="choose"
    />
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <label class="flex flex-col gap-1.5">
        <span class="ap-label">From</span>
        <input
          v-model="fromText"
          type="text"
          spellcheck="false"
          :aria-invalid="fromBad ? 'true' : undefined"
          :class="fieldClass(fromBad)"
          @change="commitFields"
          @keydown.enter="commitFields"
        />
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="ap-label">To</span>
        <input
          v-model="toText"
          type="text"
          spellcheck="false"
          :aria-invalid="toBad || order ? 'true' : undefined"
          :class="fieldClass(toBad || order)"
          @change="commitFields"
          @keydown.enter="commitFields"
        />
      </label>
    </div>
    <p v-if="fromBad || toBad || order" role="status" class="m-0 text-sm text-caution-text">
      {{
        order ? "To must be after From." : "Can’t read that time. Try 2026-10-24 06:00 or now−6h."
      }}
    </p>
    <RangeTrack
      :span="span"
      :bands="bands"
      :selected="model"
      :now="now.getTime()"
      :label="`${label}: ${fromText} to ${toText}, on a ${trackHours} hour track`"
      @select="model = $event"
      @preview="onPreview"
    />
  </fieldset>
</template>
