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
  <label class="fieldset" :for="id">
    <span class="hud-label">
      {{ label }}
      <span v-if="required" aria-hidden="true">*</span>
    </span>
    <input
      :id="id"
      class="input w-full"
      :class="{ 'input-error': error }"
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
    <span v-if="error" :id="`${id}-error`" class="text-sm text-error" role="alert">
      {{ error }}
    </span>
    <span v-else-if="hint" :id="`${id}-hint`" class="text-xs text-muted">
      {{ hint }}
    </span>
  </label>
</template>
