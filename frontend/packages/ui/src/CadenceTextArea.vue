<script setup lang="ts">
import { computed } from "vue";

/** A multi-line text field; the textarea counterpart of CadenceTextField. */
const props = withDefaults(
  defineProps<{
    id: string;
    label: string;
    modelValue: string;
    rows?: number;
    maxlength?: number;
    disabled?: boolean;
    error?: string;
    hint?: string;
    name?: string;
    placeholder?: string;
    required?: boolean;
  }>(),
  { rows: 4, disabled: false, required: false },
);
const emit = defineEmits<{ "update:modelValue": [value: string] }>();
const descriptionId = computed(() => {
  if (props.error) return `${props.id}-error`;
  if (props.hint) return `${props.id}-hint`;
  return undefined;
});
function updateValue(event: Event): void {
  emit("update:modelValue", (event.target as HTMLTextAreaElement).value);
}
</script>

<template>
  <label class="fieldset" :for="id">
    <span class="hud-label">
      {{ label }}
      <span v-if="required" aria-hidden="true">*</span>
    </span>
    <textarea
      :id="id"
      class="textarea w-full"
      :class="{ 'textarea-error': error }"
      :name="name ?? id"
      :rows="rows"
      :maxlength="maxlength"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :required="required"
      :aria-describedby="descriptionId"
      :aria-invalid="error ? 'true' : undefined"
      @input="updateValue"
    ></textarea>
    <span v-if="error" :id="`${id}-error`" class="text-sm text-error" role="alert">
      {{ error }}
    </span>
    <span v-else-if="hint" :id="`${id}-hint`" class="text-xs text-muted">
      {{ hint }}
    </span>
  </label>
</template>
