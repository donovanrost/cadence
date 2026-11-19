<script setup lang="ts">
import { fieldId } from "../field-id.ts";
import { computed, nextTick, ref, watch } from "vue";
import { dayKey, monthGrid, MONTHS, withDate } from "./calendar.ts";

/** UTC month calendar. Days are a roving-tabindex grid: arrows move, Enter/Space picks. */
const props = defineProps<{
  modelValue: number;
  today: number;
  /** `YYYY-MM-DD` days to tick (e.g. queued uplinks). */
  marked: ReadonlySet<string>;
  markedLabel: string;
}>();
const emit = defineEmits<{ "update:modelValue": [value: number] }>();

const selected = computed(() => new Date(props.modelValue));
const view = ref({ year: selected.value.getUTCFullYear(), month: selected.value.getUTCMonth() });
// Follow the selection when it moves outside the visible month (presets, typing, spinners).
watch(selected, (d) => {
  if (d.getUTCFullYear() !== view.value.year || d.getUTCMonth() !== view.value.month)
    view.value = { year: d.getUTCFullYear(), month: d.getUTCMonth() };
});
const grid = computed(() => monthGrid(view.value.year, view.value.month));
const selectedKey = computed(() =>
  dayKey(
    selected.value.getUTCFullYear(),
    selected.value.getUTCMonth(),
    selected.value.getUTCDate(),
  ),
);
const todayKey = computed(() => {
  const t = new Date(props.today);
  return dayKey(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate());
});
const root = ref<HTMLElement | null>(null);

function shiftMonth(delta: number) {
  const d = new Date(Date.UTC(view.value.year, view.value.month + delta, 1));
  view.value = { year: d.getUTCFullYear(), month: d.getUTCMonth() };
}

function pick(year: number, month: number, day: number) {
  emit("update:modelValue", withDate(props.modelValue, year, month, day));
  if (month !== view.value.month || year !== view.value.year) view.value = { year, month };
}

const STEPS: Readonly<Record<string, number>> = {
  ArrowLeft: -1,
  ArrowRight: 1,
  ArrowUp: -7,
  ArrowDown: 7,
};
async function onKey(event: KeyboardEvent) {
  const step = STEPS[event.key];
  if (step === undefined) return;
  event.preventDefault();
  const next = new Date(props.modelValue + step * 86_400_000);
  pick(next.getUTCFullYear(), next.getUTCMonth(), next.getUTCDate());
  await nextTick();
  root.value?.querySelector<HTMLElement>('[tabindex="0"]')?.focus();
}
const uid = fieldId("ap-tp-month");
</script>

<template>
  <section :aria-labelledby="uid" class="flex flex-col gap-2">
    <div class="flex items-center justify-between">
      <button
        type="button"
        aria-label="Previous month"
        class="size-8 cursor-pointer border-0 bg-transparent text-text-3 hover:text-readout max-md:hit-44"
        @click="shiftMonth(-1)"
      >
        ‹
      </button>
      <h3
        :id="uid"
        class="m-0 font-display text-md font-semibold tracking-tag uppercase"
        aria-live="polite"
      >
        {{ MONTHS[view.month] }} {{ view.year }}
      </h3>
      <button
        type="button"
        aria-label="Next month"
        class="size-8 cursor-pointer border-0 bg-transparent text-text-3 hover:text-readout max-md:hit-44"
        @click="shiftMonth(1)"
      >
        ›
      </button>
    </div>
    <div
      ref="root"
      role="grid"
      :aria-labelledby="uid"
      class="grid grid-cols-7 gap-px"
      @keydown="onKey"
    >
      <span
        v-for="d in ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']"
        :key="d"
        role="columnheader"
        class="pb-1 text-center font-mono text-2xs text-text-4 uppercase"
        >{{ d }}</span
      >
      <button
        v-for="d in grid"
        :key="d.key"
        type="button"
        role="gridcell"
        :tabindex="d.key === selectedKey ? 0 : -1"
        :aria-selected="d.key === selectedKey"
        :aria-label="`${d.key}${marked.has(d.key) ? `, ${markedLabel}` : ''}${d.key === todayKey ? ', today' : ''}`"
        class="relative flex h-9 cursor-pointer max-md:min-h-11 items-center justify-center border font-sans text-md tabular"
        :class="[
          d.key === selectedKey
            ? 'border-action bg-action font-semibold text-on-action'
            : d.key === todayKey
              ? 'border-readout bg-transparent text-readout'
              : 'border-transparent bg-transparent hover:bg-raised',
          d.inMonth || d.key === selectedKey ? '' : 'text-text-off',
          d.inMonth && d.key !== selectedKey && d.key !== todayKey ? 'text-text-2' : '',
        ]"
        @click="pick(d.year, d.month, d.day)"
      >
        {{ d.day }}
        <span
          v-if="marked.has(d.key)"
          aria-hidden="true"
          class="absolute bottom-1 h-0.5 w-3 bg-current"
        />
      </button>
    </div>
    <p
      v-if="marked.size > 0"
      class="m-0 flex items-center gap-2 font-mono text-xs text-text-4 uppercase"
    >
      <span aria-hidden="true" class="h-0.5 w-3 bg-text-3" />{{ markedLabel }}
    </p>
  </section>
</template>
