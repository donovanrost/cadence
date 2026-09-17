<script setup lang="ts">
import { useId } from "vue";

const props = withDefaults(
  defineProps<{
    id: string;
    label: string;
    options: readonly { value: string; label: string }[];
    modelValue: string | null;
    disabled?: boolean;
    required?: boolean;
    hideLabel?: boolean;
    placeholder?: string;
  }>(),
  { placeholder: "Choose a value" },
);
const emit = defineEmits<{ "update:modelValue": [value: string] }>();
const name = useId();
function select(event: Event) {
  const target = event.target;
  if (
    target instanceof HTMLSelectElement &&
    props.options.some((option) => option.value === target.value)
  )
    emit("update:modelValue", target.value);
}
</script>
<template>
  <div class="cadence-choice-field">
    <span :id="`${id}-label`" class="hud-label" :class="{ 'sr-only': hideLabel }">{{ label }}</span>
    <div
      v-if="options.length <= 6"
      :id="id"
      class="cadence-choice-field__buttons"
      role="radiogroup"
      :aria-labelledby="`${id}-label`"
    >
      <label
        v-for="(option, index) in options"
        :key="option.value"
        class="cadence-choice-field__option"
        :data-selected="modelValue === option.value"
      >
        <input
          :id="`${id}-${index}`"
          class="sr-only"
          type="radio"
          :name="name"
          :value="option.value"
          :checked="modelValue === option.value"
          :disabled="disabled"
          :required="required"
          @change="emit('update:modelValue', option.value)"
        />
        <span>{{ option.label }}</span>
      </label>
    </div>
    <select
      v-else
      :id="id"
      class="select w-full"
      :value="modelValue ?? ''"
      :disabled="disabled"
      :required="required"
      :aria-labelledby="`${id}-label`"
      @change="select"
    >
      <option value="" disabled>{{ placeholder }}</option>
      <option v-for="option in options" :key="option.value" :value="option.value">
        {{ option.label }}
      </option>
    </select>
  </div>
</template>
<style scoped>
.cadence-choice-field {
  display: grid;
  gap: var(--space-1-5, 6px);
  min-width: 0;
}
.cadence-choice-field__buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.cadence-choice-field__option {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: var(--workspace-control-height, var(--control-sm));
  max-width: 100%;
  padding: 6px 12px;
  border: 1px solid var(--control-border);
  border-radius: var(--control-radius);
  background: var(--surface-input);
  color: var(--text-subtle);
  font: 500 var(--workspace-label-size, 13px)/1.4 var(--font-mono);
  overflow-wrap: anywhere;
  cursor: pointer;
}
.cadence-choice-field__option:hover {
  border-color: var(--border-strong);
  color: var(--text-bright);
}
.cadence-choice-field__option[data-selected="true"] {
  border-color: var(--color-action);
  background: color-mix(in srgb, var(--color-action) 12%, var(--surface-input));
  color: var(--color-action);
  box-shadow: inset 0 -2px var(--color-action);
}
.cadence-choice-field__option:has(input:focus-visible) {
  outline: 2px solid var(--border-focus);
  outline-offset: 2px;
}
.cadence-choice-field__option:has(input:disabled) {
  opacity: 0.55;
  cursor: default;
}
</style>
