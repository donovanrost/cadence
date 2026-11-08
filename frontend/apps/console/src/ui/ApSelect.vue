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
    name?: string | undefined;
    hiddenLabel?: boolean | undefined;
    /** Shown as a disabled first option when nothing is chosen. */
    placeholder?: string | undefined;
  }>(),
  { disabled: false, hiddenLabel: false },
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
    <select
      :id="id"
      v-model="model"
      :name="name"
      :disabled="disabled"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="describedBy"
      class="h-[38px] border bg-well px-3 text-base text-readout focus:border-readout"
      :class="error ? 'border-caution' : 'border-line'"
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
    <p v-if="hint" :id="`${id}-hint`" class="m-0 text-sm text-text-3">{{ hint }}</p>
    <p v-if="error" :id="`${id}-error`" class="m-0 text-sm text-caution-text">{{ error }}</p>
  </div>
</template>
