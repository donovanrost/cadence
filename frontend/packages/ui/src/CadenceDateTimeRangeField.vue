<script setup lang="ts">
import { computed } from "vue";
import {
  CalendarDateTime,
  Time,
  parseDateTime,
  toCalendarDateTime,
  type DateValue,
} from "@internationalized/date";
import {
  DateRangeFieldInput,
  DateRangeFieldRoot,
  RangeCalendarCell,
  RangeCalendarCellTrigger,
  RangeCalendarGrid,
  RangeCalendarGridBody,
  RangeCalendarGridHead,
  RangeCalendarGridRow,
  RangeCalendarHeadCell,
  RangeCalendarHeader,
  RangeCalendarHeading,
  RangeCalendarNext,
  RangeCalendarPrev,
  RangeCalendarRoot,
} from "reka-ui";
import CadenceIcon from "./CadenceIcon.vue";
import type { UtcRange } from "./date-time-range";

/**
 * Picks a UTC date-time range: a calendar for the days and segmented fields for
 * exact times. Values are wall-clock UTC; the viewer's timezone never applies.
 */
const props = defineProps<{
  id: string;
  label: string;
  modelValue: UtcRange | null;
  /** Latest selectable instant, e.g. now. */
  max?: string;
  hint?: string;
  error?: string;
}>();
const emit = defineEmits<{ "update:modelValue": [value: UtcRange] }>();

const toValue = (iso: string) => parseDateTime(iso.replace(/Z$/, "").slice(0, 19));
const fromValue = (value: DateValue) => `${toCalendarDateTime(value).toString().slice(0, 19)}Z`;
const withTime = (value: DateValue, time: Time) =>
  "hour" in value ? toCalendarDateTime(value) : toCalendarDateTime(value, time);

const range = computed(() =>
  props.modelValue
    ? { start: toValue(props.modelValue.start), end: toValue(props.modelValue.end) }
    : null,
);
const maxValue = computed(() => (props.max ? toValue(props.max) : undefined));
// exactOptionalPropertyTypes: pass max-value only when there is one.
const bounds = computed(() => (maxValue.value ? { maxValue: maxValue.value } : {}));
const placeholder = computed(
  () => range.value?.end ?? maxValue.value ?? new CalendarDateTime(2026, 1, 1),
);
const describedBy = computed(() =>
  props.error ? `${props.id}-error` : props.hint ? `${props.id}-hint` : undefined,
);

type PartialRange = { start?: DateValue | undefined; end?: DateValue | undefined } | null;
const dayStart = new Time(0, 0, 0);
const dayEnd = new Time(23, 59, 59);
const timeOf = (value: CalendarDateTime) => new Time(value.hour, value.minute, value.second);

function publish(start: DateValue, end: DateValue) {
  emit("update:modelValue", {
    start: fromValue(withTime(start, dayStart)),
    end: fromValue(withTime(end, dayEnd)),
  });
}
// Picking days keeps the times already chosen; a fresh range spans whole days.
function pickDays(next: PartialRange) {
  if (!next?.start || !next.end) return;
  const current = range.value;
  publish(
    toCalendarDateTime(next.start, current ? timeOf(current.start) : dayStart),
    toCalendarDateTime(next.end, current ? timeOf(current.end) : dayEnd),
  );
}
function typed(next: PartialRange) {
  if (next?.start && next.end) publish(next.start, next.end);
}

const cell =
  "flex h-7 w-full items-center justify-center rounded-sm font-mono text-xs tabular-nums outline-none hover:bg-base-300 focus-visible:ring-1 focus-visible:ring-primary data-[outside-view]:invisible data-[disabled]:pointer-events-none data-[disabled]:text-base-content/40 data-[today]:underline data-[highlighted]:bg-primary/15 data-[selected]:bg-primary/20 data-[selection-start]:bg-primary data-[selection-start]:text-primary-content data-[selection-end]:bg-primary data-[selection-end]:text-primary-content";
const segment =
  "rounded-sm px-0.5 tabular-nums outline-none focus:bg-primary/20 focus:text-primary data-[placeholder]:text-base-content/40";
</script>

<template>
  <div
    :id="id"
    class="grid gap-3"
    role="group"
    :aria-labelledby="`${id}-label`"
    :aria-describedby="describedBy"
  >
    <span :id="`${id}-label`" class="hud-label">{{ label }}</span>
    <RangeCalendarRoot
      v-slot="{ grid, weekDays }"
      :model-value="range"
      :placeholder="placeholder"
      v-bind="bounds"
      :week-starts-on="1"
      locale="en-GB"
      fixed-weeks
      weekday-format="narrow"
      @update:model-value="pickDays"
    >
      <RangeCalendarHeader class="mb-1 flex items-center justify-between">
        <RangeCalendarPrev class="cadence-icon-button"
          ><CadenceIcon name="hero-chevron-left" label="Previous month"
        /></RangeCalendarPrev>
        <RangeCalendarHeading class="text-sm font-medium" />
        <RangeCalendarNext class="cadence-icon-button"
          ><CadenceIcon name="hero-chevron-right" label="Next month"
        /></RangeCalendarNext>
      </RangeCalendarHeader>
      <RangeCalendarGrid
        v-for="month in grid"
        :key="month.value.toString()"
        class="w-full border-collapse"
      >
        <RangeCalendarGridHead>
          <RangeCalendarGridRow class="grid grid-cols-7">
            <RangeCalendarHeadCell
              v-for="day in weekDays"
              :key="day"
              class="text-center text-[0.65rem] font-normal text-base-content/60"
            >
              {{ day }}
            </RangeCalendarHeadCell>
          </RangeCalendarGridRow>
        </RangeCalendarGridHead>
        <RangeCalendarGridBody>
          <RangeCalendarGridRow
            v-for="(week, index) in month.rows"
            :key="index"
            class="grid grid-cols-7 gap-y-0.5"
          >
            <RangeCalendarCell v-for="date in week" :key="date.toString()" :date="date">
              <RangeCalendarCellTrigger :day="date" :month="month.value" :class="cell" />
            </RangeCalendarCell>
          </RangeCalendarGridRow>
        </RangeCalendarGridBody>
      </RangeCalendarGrid>
    </RangeCalendarRoot>
    <DateRangeFieldRoot
      v-slot="{ segments }"
      :model-value="range"
      v-bind="bounds"
      :placeholder="placeholder"
      granularity="second"
      :hour-cycle="24"
      locale="en-GB"
      class="grid gap-1.5"
      @update:model-value="typed"
    >
      <div
        v-for="type in ['start', 'end'] as const"
        :key="type"
        class="input flex w-full items-center gap-0 font-mono text-xs"
      >
        <span class="hud-label mr-2 w-9">{{ type === "start" ? "From" : "To" }}</span>
        <template v-for="(item, index) in segments[type]" :key="index">
          <DateRangeFieldInput
            v-if="item.part === 'literal'"
            :part="item.part"
            :type="type"
            class="text-base-content/50"
          >
            {{ item.value }}
          </DateRangeFieldInput>
          <DateRangeFieldInput v-else :part="item.part" :type="type" :class="segment">{{
            item.value
          }}</DateRangeFieldInput>
        </template>
        <span class="ml-auto pl-2 text-base-content/60">UTC</span>
      </div>
    </DateRangeFieldRoot>
    <p v-if="error" :id="`${id}-error`" role="alert" class="text-xs text-error">{{ error }}</p>
    <p v-else-if="hint" :id="`${id}-hint`" class="text-xs text-base-content/60">{{ hint }}</p>
  </div>
</template>
