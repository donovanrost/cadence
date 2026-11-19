<script setup lang="ts">
import { computed } from "vue";
import { fieldId } from "./field-id.ts";

/** Labelled multi-line text. Same box as ApField; sans 14. */
const props = withDefaults(
  defineProps<{
    label: string;
    rows?: number | undefined;
    hint?: string | undefined;
    error?: string | null | undefined;
    required?: boolean | undefined;
    placeholder?: string | undefined;
    maxlength?: number | undefined;
  }>(),
  { rows: 3, required: false },
);
const model = defineModel<string>({ required: true });
const id = fieldId("ap-textarea");
const describedBy = computed(
  () =>
    [props.error ? `${id}-error` : null, props.hint ? `${id}-hint` : null]
      .filter(Boolean)
      .join(" ") || undefined,
);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <label :for="id" class="ap-label">{{ label }}</label>
    <textarea
      :id="id"
      v-model="model"
      :rows="rows"
      :required="required"
      :placeholder="placeholder"
      :maxlength="maxlength"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="describedBy"
      class="resize-y border bg-well p-2.5 font-sans text-base text-readout outline-none placeholder:text-text-4 focus:border-readout"
      :class="error ? 'border-caution' : 'border-line'"
    />
    <p v-if="hint" :id="`${id}-hint`" class="m-0 text-sm text-text-3">{{ hint }}</p>
    <p v-if="error" :id="`${id}-error`" class="m-0 text-sm text-caution-text">{{ error }}</p>
  </div>
</template>
