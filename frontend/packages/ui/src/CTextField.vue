<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(
  defineProps<{
    autocomplete?: string;
    disabled?: boolean;
    error?: string;
    hint?: string;
    id: string;
    label: string;
    modelValue: string;
    name?: string;
    placeholder?: string;
    required?: boolean;
    type?: "email" | "password" | "text";
  }>(),
  {
    autocomplete: undefined,
    disabled: false,
    error: undefined,
    hint: undefined,
    name: undefined,
    placeholder: undefined,
    required: false,
    type: "text",
  },
);

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const descriptionId = computed(() => {
  if (props.error) return `${props.id}-error`;
  if (props.hint) return `${props.id}-hint`;
  return undefined;
});

function updateValue(event: Event): void {
  emit("update:modelValue", (event.target as HTMLInputElement).value);
}
</script>

<template>
  <label class="cui-text-field" :for="id">
    <span class="cui-text-field__label">
      {{ label }}
      <span v-if="required" aria-hidden="true">*</span>
    </span>
    <input
      :id="id"
      class="cui-text-field__control"
      :class="{ 'cui-text-field__control--error': error }"
      :name="name ?? id"
      :type="type"
      :value="modelValue"
      :autocomplete="autocomplete"
      :placeholder="placeholder"
      :disabled="disabled"
      :required="required"
      :aria-describedby="descriptionId"
      :aria-invalid="error ? 'true' : undefined"
      @input="updateValue"
    />
    <span v-if="error" :id="`${id}-error`" class="cui-text-field__message" role="alert">
      {{ error }}
    </span>
    <span v-else-if="hint" :id="`${id}-hint`" class="cui-text-field__hint">
      {{ hint }}
    </span>
  </label>
</template>

<style scoped>
.cui-text-field {
  display: grid;
  gap: var(--cadence-space-2);
  color: var(--cadence-color-text);
}

.cui-text-field__label {
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  font-weight: 650;
  letter-spacing: var(--cadence-tracking-label);
  line-height: 1.2;
  text-transform: uppercase;
}

.cui-text-field__control {
  width: 100%;
  min-height: 48px;
  padding: 0 var(--cadence-space-4);
  border: 1px solid var(--cadence-color-border-subtle);
  border-radius: 0;
  outline: 0;
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface);
  font-size: var(--cadence-type-body-md);
  transition:
    border-color var(--cadence-transition-fast),
    background var(--cadence-transition-fast);
}

.cui-text-field__control::placeholder {
  color: var(--cadence-color-text-muted);
}

.cui-text-field__control:hover:not(:disabled) {
  border-color: var(--cadence-color-border);
}

.cui-text-field__control:focus-visible {
  border-color: var(--cadence-color-signal);
  outline: 2px solid var(--cadence-color-signal);
  outline-offset: 2px;
}

.cui-text-field__control--error {
  border-color: var(--cadence-color-danger);
}

.cui-text-field__control:disabled {
  color: var(--cadence-color-text-muted);
  background: var(--cadence-color-surface-inset);
  cursor: not-allowed;
}

.cui-text-field__hint,
.cui-text-field__message {
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-body-sm);
  line-height: var(--cadence-leading-copy);
}

.cui-text-field__hint {
  color: var(--cadence-color-text-muted);
}

.cui-text-field__message {
  color: var(--cadence-color-danger);
}
</style>
