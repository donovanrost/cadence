<script setup lang="ts" generic="Value extends string">
import { computed } from "vue";
import { fieldId } from "./field-id.ts";

export type ApSelectOption<V extends string> = Readonly<{
  value: V;
  label: string;
  disabled?: boolean;
}>;

const props = withDefaults(
  defineProps<{
    label: string;
    options: readonly ApSelectOption<Value>[];
    hint?: string | undefined;
    error?: string | null | undefined;
    disabled?: boolean | undefined;
    /** Read as required (aria-required); for the disabled-reason pattern, never aria-invalid while untouched (ux A6). */
    required?: boolean | undefined;
    name?: string | undefined;
    hiddenLabel?: boolean | undefined;
    /** compact = 32px (panel headers, filters), standard = 38px (forms). */
    size?: "compact" | "standard" | undefined;
    /** Mono 12 for ids and planes; sans 14 for words. */
    mono?: boolean | undefined;
    /** Shown as a disabled first option when nothing is chosen. */
    placeholder?: string | undefined;
  }>(),
  { disabled: false, hiddenLabel: false, size: "standard", mono: false },
);
const model = defineModel<Value | "">({ required: true });
const id = fieldId("ap-select");
const describedBy = computed(
  () =>
    [props.error ? `${id}-error` : null, props.hint ? `${id}-hint` : null]
      .filter(Boolean)
      .join(" ") || undefined,
);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <label :for="id" class="ap-label" :class="hiddenLabel ? 'sr-only' : ''">{{ label }}</label>
    <div class="relative flex">
      <select
        :id="id"
        v-model="model"
        :name="name"
        :disabled="disabled"
        :required="required"
        :aria-required="required ? 'true' : undefined"
        :aria-invalid="error ? 'true' : undefined"
        :aria-describedby="describedBy"
        class="w-full cursor-pointer appearance-none rounded-none [color-scheme:dark] border bg-well pr-8 pl-3 text-readout focus:border-readout disabled:cursor-not-allowed disabled:text-text-off"
        :class="[
          error ? 'border-caution' : 'border-line',
          size === 'compact' ? 'h-8 max-md:h-11' : 'h-[38px] max-md:h-11',
          mono ? 'font-mono text-sm' : 'font-sans text-base',
        ]"
      >
        <option v-if="placeholder" value="" disabled>{{ placeholder }}</option>
        <option
          v-for="option in options"
          :key="option.value"
          :value="option.value"
          :disabled="option.disabled"
        >
          {{ option.label }}
        </option>
      </select>
      <svg
        aria-hidden="true"
        width="10"
        height="10"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
        class="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-text-4"
      >
        <path d="m6 9 6 6 6-6" />
      </svg>
    </div>
    <p v-if="hint" :id="`${id}-hint`" class="m-0 text-sm text-text-3">{{ hint }}</p>
    <p v-if="error" :id="`${id}-error`" class="m-0 text-sm text-caution-text">{{ error }}</p>
  </div>
</template>
