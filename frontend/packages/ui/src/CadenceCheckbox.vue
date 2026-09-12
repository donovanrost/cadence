<script setup lang="ts">
import { CheckboxIndicator, CheckboxRoot } from "reka-ui";
import { computed, useId } from "vue";

const props = withDefaults(
  defineProps<{
    disabled?: boolean;
    id?: string;
    modelValue: boolean;
    presentation?: "control" | "row";
  }>(),
  {
    disabled: false,
    presentation: "control",
  },
);

const emit = defineEmits<{
  "update:modelValue": [value: boolean];
}>();

const generatedId = useId();
const controlId = computed(() => props.id ?? generatedId);

function updateValue(value: boolean | "indeterminate"): void {
  emit("update:modelValue", value === true);
}
</script>

<template>
  <div
    :class="['cadence-checkbox', `cadence-checkbox--${presentation}`]"
    :data-state="modelValue ? 'checked' : 'unchecked'"
    :data-disabled="disabled || undefined"
  >
    <CheckboxRoot
      :id="controlId"
      class="checkbox cadence-checkbox__control"
      :model-value="modelValue"
      :disabled="disabled"
      @update:model-value="updateValue"
    >
      <CheckboxIndicator class="cadence-checkbox__indicator">
        <span></span>
      </CheckboxIndicator>
    </CheckboxRoot>
    <label class="cadence-checkbox__label" :for="controlId"><slot /></label>
  </div>
</template>

<style scoped>
.cadence-checkbox {
  display: inline-flex;
  align-items: center;
  gap: var(--space-3);
  color: var(--color-base-content);
  font-size: var(--type-body-md);
  line-height: 1.4;
  cursor: pointer;
}

.cadence-checkbox--row {
  display: grid;
}

.cadence-checkbox--row .cadence-checkbox__label {
  display: contents;
}

.cadence-checkbox__control {
  display: grid;
  width: 1.25rem;
  height: 1.25rem;
  margin: 0;
  padding: 0;
  border: 1px solid var(--control-border);
  border-radius: var(--control-radius);
  color: var(--text-inverse);
  background: transparent;
  cursor: pointer;
  place-items: center;
  transition:
    border-color var(--transition-fast),
    background var(--transition-fast);
}

.cadence-checkbox__control:hover:not(:disabled) {
  border-color: var(--color-action);
}

.cadence-checkbox__control[data-state="checked"] {
  border-color: var(--color-action);
  background: var(--color-action);
}

.cadence-checkbox__indicator span {
  display: block;
  width: 8px;
  height: 4px;
  border-bottom: 2px solid currentcolor;
  border-left: 2px solid currentcolor;
  transform: translateY(-1px) rotate(-45deg);
}

.cadence-checkbox__label {
  cursor: pointer;
  user-select: none;
}

.cadence-checkbox[data-disabled] {
  color: var(--text-muted);
  opacity: 0.55;
  cursor: not-allowed;
}

.cadence-checkbox[data-disabled] .cadence-checkbox__control,
.cadence-checkbox[data-disabled] .cadence-checkbox__label {
  cursor: not-allowed;
}
</style>
