<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{
  id: string;
  label: string;
  /** An ISO UTC timestamp, or an empty string for an unrestricted time. */
  modelValue: string;
  min?: string;
  max?: string;
  name?: string;
  disabled?: boolean;
  required?: boolean;
  error?: string;
  hint?: string;
}>();
const emit = defineEmits<{
  "update:modelValue": [value: string];
  /** An incomplete edit must invalidate a caller's prepared action, too. */
  invalid: [];
}>();
const descriptionId = computed(() =>
  props.error ? `${props.id}-error` : props.hint ? `${props.id}-hint` : undefined,
);

function normalize(value: string): string {
  if (!value) return "";
  const [whole, fraction] = (value.length === 16 ? `${value}:00` : value).split(".");
  const significant = fraction?.replace(/0+$/, "");
  return `${whole}${significant ? `.${significant}` : ""}`;
}
function nativeValue(value: string): string {
  // datetime-local edits UTC wall-clock fields; never apply the computer's timezone.
  // Native pickers support milliseconds. Keep finer precision in the model.
  return normalize(value.replace(/Z$/, "").slice(0, 23));
}
function updateValue(event: Event): void {
  if (!(event.target instanceof HTMLInputElement)) return;
  if (event.target.validity.badInput) {
    emit("invalid");
    return;
  }
  let value = normalize(event.target.value);
  if (value === nativeValue(props.modelValue)) return;
  if (value) {
    const precision = props.modelValue.match(/\.(\d{4,6})Z$/)?.[1];
    // Changing a date or whole second must not round an existing microsecond value.
    if (precision && (value.split(".")[1] ?? "").padEnd(3, "0") === precision.slice(0, 3))
      value = `${value.split(".")[0]}.${precision}`;
  }
  emit("update:modelValue", value ? `${value}Z` : "");
}
</script>

<template>
  <label class="fieldset" :for="id">
    <span class="hud-label"
      >{{ label }} (UTC)<span v-if="required" aria-hidden="true"> *</span></span
    >
    <input
      :id="id"
      class="input w-full"
      :class="{ 'input-error': error }"
      type="datetime-local"
      step="0.001"
      :name="name ?? id"
      :value="nativeValue(modelValue)"
      :min="min ? nativeValue(min) : undefined"
      :max="max ? nativeValue(max) : undefined"
      :disabled="disabled"
      :required="required"
      :aria-describedby="descriptionId"
      :aria-invalid="error ? 'true' : undefined"
      @input="updateValue"
    />
    <span v-if="error" :id="`${id}-error`" class="text-sm text-error" role="alert">{{
      error
    }}</span>
    <span v-else-if="hint" :id="`${id}-hint`" class="text-xs text-muted">{{ hint }}</span>
  </label>
</template>
