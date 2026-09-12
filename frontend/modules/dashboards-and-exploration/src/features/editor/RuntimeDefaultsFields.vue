<script setup lang="ts">
import { computed } from "vue";
import {
  parseRuntimeDefaults,
  runtimeDefaultsMaxBytes,
  runtimeQuickFields,
  setRuntimeDefault,
} from "./runtime-defaults";
const props = defineProps<{ modelValue: string }>();
const emit = defineEmits<{ "update:modelValue": [value: string] }>();
const parsed = computed(() => {
  try {
    return { value: parseRuntimeDefaults(props.modelValue), error: "" };
  } catch (error) {
    return {
      value: null,
      error: error instanceof Error ? error.message : "Check runtime defaults.",
    };
  }
});
function current(context: string, key: string): string {
  const section = parsed.value.value?.[context];
  if (section === null || typeof section !== "object" || Array.isArray(section)) return "";
  const value = (section as Record<string, unknown>)[key];
  return value == null ? "" : typeof value === "string" ? value : "[invalid value]";
}
function available(context: string): boolean {
  const section = parsed.value.value?.[context];
  return (
    parsed.value.value !== null &&
    (section == null || (typeof section === "object" && !Array.isArray(section)))
  );
}
function change(context: string, key: string, event: Event) {
  emit(
    "update:modelValue",
    setRuntimeDefault(props.modelValue, context, key, (event.target as HTMLSelectElement).value),
  );
}
</script>
<template>
  <div id="editor-runtime-fields" class="space-y-4 min-w-0">
    <p id="editor-runtime-help" class="text-xs leading-relaxed text-base-content/65">
      Defaults apply when a viewer or widget does not supply its own context. These are saved
      dashboard settings, not controls for the current viewing session. Publish separately to make
      them available to viewers.
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <label
        v-for="field in runtimeQuickFields"
        :key="`${field.context}.${field.key}`"
        :for="`editor-runtime-${field.context}-${field.key}`"
        class="grid gap-1.5 text-xs min-w-0"
      >
        {{ field.label }}
        <select
          :id="`editor-runtime-${field.context}-${field.key}`"
          :value="current(field.context, field.key)"
          :disabled="!available(field.context)"
          class="select select-bordered select-sm w-full"
          @change="change(field.context, field.key, $event)"
        >
          <option value="" :selected="current(field.context, field.key) === ''">Unspecified</option>
          <option
            v-if="
              current(field.context, field.key) &&
              !(field.values as readonly string[]).includes(current(field.context, field.key))
            "
            :value="current(field.context, field.key)"
            selected
          >
            Unsupported: {{ current(field.context, field.key) }}
          </option>
          <option
            v-for="value in field.values"
            :key="value"
            :value="value"
            :selected="current(field.context, field.key) === value"
          >
            {{ value.replaceAll("_", " ") }}
          </option>
        </select>
      </label>
    </div>
    <p class="text-xs leading-relaxed text-base-content/65">
      Range/archive times, replay IDs, source bindings, operational scope, overlays and comparisons
      are configured in the complete document below. Quick controls preserve those settings. A
      default does not grant access to a resource or data source.
    </p>
    <label for="editor-runtime-json" class="grid gap-2 text-xs">
      <span class="flex flex-wrap justify-between gap-2 font-mono uppercase tracking-wider">
        Full defaults document <span class="text-base-content/65">JSON · 32 KiB maximum</span>
      </span>
      <textarea
        id="editor-runtime-json"
        :value="modelValue"
        rows="16"
        :maxlength="runtimeDefaultsMaxBytes"
        spellcheck="false"
        autocomplete="off"
        autocapitalize="off"
        aria-describedby="editor-runtime-help editor-runtime-json-help editor-runtime-validation"
        :aria-invalid="!!parsed.error"
        class="textarea textarea-bordered w-full font-mono text-xs leading-relaxed"
        @input="emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)"
      />
    </label>
    <p id="editor-runtime-json-help" class="text-xs text-base-content/65">
      Use an object, not an array. Removing a field leaves it unspecified. An empty object clears
      all saved defaults. Save draft is the only operation that persists these edits.
    </p>
    <p
      id="editor-runtime-validation"
      role="status"
      class="text-xs"
      :class="parsed.error ? 'text-warning' : 'text-base-content/65'"
    >
      {{
        parsed.error || "JSON structure is valid. Phoenix validates domain settings when you save."
      }}
    </p>
  </div>
</template>
