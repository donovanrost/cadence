<script setup lang="ts">
import { computed } from "vue";
import { readNumber } from "./command/number.ts";
import { fieldId } from "./field-id.ts";

/**
 * Catalog-driven number (Compose arguments, profile values): unit inside, a min…max range bar
 * with the value tick, and an out-of-range caution. The model is the raw text; read the parsed
 * value with readNumber() so out-of-range values can't be staged.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    unit?: string | undefined;
    min?: number | undefined;
    max?: number | undefined;
    integer?: boolean | undefined;
    hint?: string | undefined;
    hiddenLabel?: boolean | undefined;
  }>(),
  { integer: false, hiddenLabel: false },
);
const model = defineModel<string>({ required: true });
const id = fieldId("ap-number");
const reading = computed(() => readNumber(model.value, props));
const range = computed(() =>
  props.min !== undefined && props.max !== undefined
    ? `${props.min}–${props.max}${props.unit ? ` ${props.unit}` : ""}`
    : null,
);
const error = computed(() => {
  if (reading.value.kind === "invalid")
    return props.integer ? "Enter a whole number." : "Enter a number.";
  if (reading.value.kind === "out_of_range")
    return `Out of range. Allowed: ${range.value ?? "see catalog"}.`;
  return null;
});
const tick = computed(() => {
  const r = reading.value;
  if (props.min === undefined || props.max === undefined || props.max <= props.min) return null;
  if (r.kind !== "ok" && r.kind !== "out_of_range") return null;
  return Math.max(0, Math.min(100, ((r.value - props.min) / (props.max - props.min)) * 100));
});
function onInput(event: Event) {
  if (event.target instanceof HTMLInputElement) model.value = event.target.value;
}
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <label :for="id" class="ap-label" :class="hiddenLabel ? 'sr-only' : ''">{{ label }}</label>
    <div
      class="flex h-[38px] items-center border bg-well focus-within:border-readout max-md:h-11"
      :class="error ? 'border-caution' : 'border-line'"
    >
      <input
        :id="id"
        :value="model"
        type="text"
        :inputmode="integer ? 'numeric' : 'decimal'"
        autocomplete="off"
        :aria-invalid="error ? 'true' : undefined"
        :aria-describedby="`${id}-range${error ? ` ${id}-error` : ''}`"
        class="h-full min-w-0 flex-1 border-0 bg-transparent px-3 font-mono text-base text-readout outline-none"
        @input="onInput"
      />
      <span v-if="unit" class="pr-3 font-mono text-sm text-text-4">{{ unit }}</span>
    </div>
    <div v-if="range" aria-hidden="true" class="relative h-1 bg-hairline">
      <span
        v-if="tick !== null"
        class="absolute -top-1 h-3 w-0.5"
        :class="reading.kind === 'out_of_range' ? 'bg-caution' : 'bg-readout'"
        :style="{ left: `calc(${tick}% - 1px)` }"
      />
    </div>
    <p
      :id="`${id}-range`"
      class="m-0 flex justify-between font-mono text-xs text-text-4"
      :class="range ? '' : 'sr-only'"
    >
      <span>{{ min ?? "" }}</span
      ><span>{{ hint ?? (range ? `Range ${range}` : "") }}</span
      ><span>{{ max ?? "" }}</span>
    </p>
    <p v-if="error" :id="`${id}-error`" class="m-0 text-sm text-caution-text">{{ error }}</p>
  </div>
</template>
