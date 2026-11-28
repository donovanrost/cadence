<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout, ApField } from "@/ui";
import { inputModeFor, ratioSlip, type SchemaField } from "./kindSchema.ts";

/** One typed text field of a schema form; a percent typed as a fraction gets ux's inline hint. */
defineProps<{ field: SchemaField; hint: string | undefined; error: string | null }>();
const text = defineModel<string>({ required: true });
const unitLabel = (f: SchemaField) =>
  f.unit === "s"
    ? "duration"
    : f.unit === "micros"
      ? "amount"
      : f.unit === "ratio"
        ? "%"
        : (f.unit ?? undefined);
/** Numbers, times and lists read in mono (ids and figures). */
const isMono = (f: SchemaField) =>
  ["integer", "number", "datetime", "time", "list"].includes(f.type);
// a11y C/A5: applying the fix removes the callout and its focused button; put focus back in the field.
const box = ref<HTMLElement | null>(null);
function applyFix(fix: string) {
  text.value = fix;
  box.value?.querySelector("input")?.focus();
}
</script>

<template>
  <div ref="box" class="flex flex-col gap-2">
    <ApField
      v-model="text"
      :label="field.label"
      :mono="isMono(field)"
      :unit="unitLabel(field)"
      :inputmode="inputModeFor(field)"
      :hint="hint"
      :error="error"
      :required="field.required"
    />
    <ApCallout v-if="ratioSlip(field, text)" tone="caution">
      {{ ratioSlip(field, text)?.line }}
      <template #action>
        <ApButton size="compact" @click="applyFix(ratioSlip(field, text)?.fix ?? text)">{{
          ratioSlip(field, text)?.label
        }}</ApButton>
      </template>
    </ApCallout>
  </div>
</template>
