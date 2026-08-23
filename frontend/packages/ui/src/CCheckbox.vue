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
    id: undefined,
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
    :class="['cui-checkbox', `cui-checkbox--${presentation}`]"
    :data-state="modelValue ? 'checked' : 'unchecked'"
    :data-disabled="disabled || undefined"
  >
    <CheckboxRoot
      :id="controlId"
      class="cui-checkbox__control"
      :model-value="modelValue"
      :disabled="disabled"
      @update:model-value="updateValue"
    >
      <CheckboxIndicator class="cui-checkbox__indicator">
        <span></span>
      </CheckboxIndicator>
    </CheckboxRoot>
    <label class="cui-checkbox__label" :for="controlId"><slot /></label>
  </div>
</template>

<style scoped>
.cui-checkbox {
  display: inline-flex;
  align-items: center;
  gap: var(--cadence-space-2);
  color: var(--cadence-color-text-secondary);
  cursor: pointer;
}

.cui-checkbox--row {
  display: grid;
}

.cui-checkbox--row .cui-checkbox__label {
  display: contents;
}

.cui-checkbox__control {
  display: grid;
  width: 14px;
  height: 14px;
  margin: 0;
  padding: 0;
  border: 1px solid var(--cadence-color-text-muted);
  border-radius: 0;
  color: #16130e;
  background: transparent;
  cursor: pointer;
  place-items: center;
  transition:
    border-color var(--cadence-transition-fast),
    background var(--cadence-transition-fast);
}

.cui-checkbox__control[data-state="checked"] {
  border-color: var(--cadence-color-accent);
  background: var(--cadence-color-accent);
}

.cui-checkbox__indicator span {
  display: block;
  width: 6px;
  height: 3px;
  border-bottom: 1.5px solid currentcolor;
  border-left: 1.5px solid currentcolor;
  transform: translateY(-1px) rotate(-45deg);
}

.cui-checkbox__label {
  cursor: pointer;
}

.cui-checkbox[data-disabled] {
  opacity: 0.45;
  cursor: not-allowed;
}

.cui-checkbox[data-disabled] .cui-checkbox__control,
.cui-checkbox[data-disabled] .cui-checkbox__label {
  cursor: not-allowed;
}
</style>
