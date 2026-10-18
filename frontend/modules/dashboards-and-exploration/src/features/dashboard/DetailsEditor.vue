<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceChoiceField from "@cadence/ui/CadenceChoiceField.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { DetailsChange } from "./contracts";
import { parseRuntimeDefaults, runtimeQuickFields, setRuntimeDefault } from "./runtime-defaults";

const props = defineProps<{
  name: string;
  description: string;
  defaultsJson: string;
  pending: boolean;
  settingsHref: string;
}>();
const emit = defineEmits<{ apply: [change: DetailsChange]; cancel: [] }>();
const name = ref(props.name);
const description = ref(props.description);
const json = ref(props.defaultsJson);
const parsed = computed(() => {
  try {
    return parseRuntimeDefaults(json.value);
  } catch {
    return null;
  }
});
function current(context: string, key: string): string {
  const section = parsed.value?.[context];
  if (section === null || typeof section !== "object" || Array.isArray(section)) return "";
  const value = (section as Record<string, unknown>)[key];
  return typeof value === "string" ? value : "";
}
function change(context: string, key: string, value: string) {
  try {
    json.value = setRuntimeDefault(json.value, context, key, value === "unset" ? "" : value);
  } catch {
    /* an unrepairable context stays as authored; Settings exposes the full document */
  }
}
const options = (values: readonly string[]) => [
  { value: "unset", label: "Not set" },
  ...values.map((v) => ({ value: v, label: v.replaceAll("_", " ") })),
];
function apply() {
  const renamed = name.value.trim() !== props.name || description.value !== props.description;
  emit("apply", {
    rename: renamed ? { name: name.value.trim(), description: description.value } : null,
    defaults: json.value === props.defaultsJson ? null : json.value,
  });
}
</script>

<template>
  <form class="space-y-5" @submit.prevent="apply">
    <section class="space-y-3">
      <CadenceTextField id="dashboard-name" v-model="name" label="Name" required />
      <CadenceTextField id="dashboard-description" v-model="description" label="Description" />
    </section>
    <section class="space-y-3 border-t border-base-300/60 pt-4">
      <span class="hud-label">Runtime defaults</span>
      <p class="text-xs text-base-content/70">
        Used when the viewer's URL does not choose a context.
        <a :href="settingsHref" class="text-primary hover:underline"
          >Edit the full defaults document</a
        >.
      </p>
      <CadenceChoiceField
        v-for="field in runtimeQuickFields"
        :id="`dashboard-default-${field.context}-${field.key}`"
        :key="`${field.context}.${field.key}`"
        :label="field.label"
        :model-value="current(field.context, field.key) || 'unset'"
        :options="options(field.values)"
        :disabled="!parsed"
        @update:model-value="(value) => change(field.context, field.key, value)"
      />
    </section>
    <footer class="flex justify-end gap-2 border-t border-base-300/60 pt-4">
      <CadenceButton variant="quiet" size="sm" @click="emit('cancel')">Cancel</CadenceButton>
      <CadenceButton
        type="submit"
        variant="primary"
        size="sm"
        :loading="pending"
        :disabled="!name.trim()"
        >Apply</CadenceButton
      >
    </footer>
  </form>
</template>
