<script setup lang="ts">
import { computed } from "vue";
import { fieldId } from "./field-id.ts";

/**
 * Labelled text input. `mono` for ids and numbers. `error` renders the caution border and the
 * message beneath, wired with aria-invalid / aria-describedby. `unit` shows inside, right-aligned.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    type?: "text" | "email" | "password" | "search" | "number" | "url" | undefined;
    mono?: boolean | undefined;
    unit?: string | undefined;
    hint?: string | undefined;
    error?: string | null | undefined;
    placeholder?: string | undefined;
    required?: boolean | undefined;
    disabled?: boolean | undefined;
    name?: string | undefined;
    autocomplete?: string | undefined;
    inputmode?: "text" | "numeric" | "decimal" | "search" | "email" | "url" | undefined;
    hiddenLabel?: boolean | undefined;
  }>(),
  { type: "text", mono: false, required: false, disabled: false, hiddenLabel: false },
);
const model = defineModel<string>({ required: true });

/** Always emit the raw text: v-model on a dynamic `type="number"` would cast to a Number. */
function onInput(event: Event) {
  if (event.target instanceof HTMLInputElement) model.value = event.target.value;
}

const id = fieldId("ap-field");
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
    <div
      class="flex h-[38px] items-center border bg-well max-md:h-11 focus-within:border-readout"
      :class="[error ? 'border-caution' : 'border-line', disabled ? 'opacity-60' : '']"
    >
      <input
        :id="id"
        :value="model"
        :type="type"
        @input="onInput"
        :name="name"
        :placeholder="placeholder"
        :required="required"
        :aria-required="required ? 'true' : undefined"
        :disabled="disabled"
        :autocomplete="autocomplete"
        :inputmode="inputmode"
        :aria-invalid="error ? 'true' : undefined"
        :aria-describedby="describedBy"
        class="h-full min-w-0 flex-1 border-0 bg-transparent px-3 text-base text-readout outline-none placeholder:text-text-4"
        :class="mono ? 'font-mono' : 'font-sans'"
      />
      <span v-if="unit" class="pr-3 font-mono text-sm text-text-4">{{ unit }}</span>
    </div>
    <p v-if="hint" :id="`${id}-hint`" class="m-0 text-sm text-text-3">{{ hint }}</p>
    <p v-if="error" :id="`${id}-error`" class="m-0 text-sm text-caution-text">{{ error }}</p>
  </div>
</template>
