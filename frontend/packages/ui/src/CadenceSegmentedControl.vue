<script setup lang="ts">
import { useId } from "vue";

withDefaults(
  defineProps<{
    label: string;
    modelValue: string;
    options: readonly { value: string; label: string; disabled?: boolean }[];
    disabled?: boolean;
    size?: "xs" | "sm";
  }>(),
  { size: "sm" },
);
const emit = defineEmits<{ "update:modelValue": [value: string] }>();
const name = useId();
</script>
<template>
  <div class="cadence-segmented-control" :data-size="size" role="radiogroup" :aria-label="label">
    <label
      v-for="option in options"
      :key="option.value"
      class="cadence-segmented-control__option"
      :data-selected="modelValue === option.value"
    >
      <input
        type="radio"
        :name="name"
        :value="option.value"
        :checked="modelValue === option.value"
        :disabled="disabled || option.disabled"
        @change="emit('update:modelValue', option.value)"
      />
      <span>{{ option.label }}</span>
    </label>
  </div>
</template>
<style scoped>
.cadence-segmented-control {
  display: inline-flex;
  align-items: stretch;
  max-width: 100%;
  padding: 2px;
  gap: 2px;
  border: 1px solid var(--control-border);
  border-radius: var(--control-radius);
  background: var(--surface-base);
  font: 550 12px/1.3 var(--font-sans);
}
.cadence-segmented-control__option {
  position: relative;
  display: flex;
  flex: 1;
  align-items: center;
  justify-content: center;
  min-width: 0;
  min-height: var(--control-sm);
  padding: 3px 10px;
  border: 1px solid transparent;
  border-radius: max(1px, calc(var(--control-radius) - 2px));
  color: var(--text-subtle);
  white-space: nowrap;
  cursor: pointer;
}
.cadence-segmented-control__option input {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  margin: 0;
  opacity: 0;
  cursor: inherit;
}
.cadence-segmented-control__option:hover {
  color: var(--text-bright);
}
.cadence-segmented-control__option[data-selected="true"] {
  border-color: var(--border-default);
  background: var(--surface-raised);
  color: var(--text-bright);
}
.cadence-segmented-control__option:has(input:focus-visible) {
  outline: 2px solid var(--border-focus);
  outline-offset: 2px;
  z-index: 1;
}
.cadence-segmented-control__option:has(input:disabled) {
  opacity: 0.5;
  cursor: default;
}
.cadence-segmented-control[data-size="xs"] {
  font-size: 11px;
}
.cadence-segmented-control[data-size="xs"] .cadence-segmented-control__option {
  min-height: 22px;
  padding: 2px 7px;
}
</style>
