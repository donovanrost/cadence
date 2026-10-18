<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceChoiceField from "@cadence/ui/CadenceChoiceField.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { OutlineSection, ScopeOption, WidgetFields, WidgetInput } from "./contracts";
import { bindsObservables, typeOptions } from "./widget-form";
import ObservableSearch from "./ObservableSearch.vue";
import WidgetBindingFields from "./WidgetBindingFields.vue";
import WidgetDisplayFields from "./WidgetDisplayFields.vue";

type Choice = { value: string; label: string; description: string };
const props = defineProps<{
  initial: WidgetFields;
  observables: readonly string[];
  sections: readonly OutlineSection[];
  scopeOptions: readonly ScopeOption[];
  creating: boolean;
  pending: boolean;
  search: (query: string, fields: WidgetFields) => Promise<{ options: Choice[]; more: boolean }>;
}>();
const emit = defineEmits<{ apply: [input: WidgetInput]; cancel: [] }>();

const fields = ref<WidgetFields>({ ...props.initial });
const selected = ref<string[]>([...props.observables]);
const sectionOptions = computed(() => [
  { value: "", label: "Unsectioned" },
  ...props.sections.map((s) => ({ value: s.id, label: s.title })),
]);
const missing = computed(() =>
  !fields.value.title.trim()
    ? "Give the widget a title."
    : bindsObservables(fields.value.type) && !selected.value.length
      ? "Bind at least one observable."
      : "",
);
function apply() {
  if (missing.value) return;
  const observables = bindsObservables(fields.value.type) ? selected.value : [];
  emit("apply", { fields: { ...fields.value, title: fields.value.title.trim() }, observables });
}
</script>

<template>
  <form class="space-y-5" @submit.prevent="apply">
    <section class="space-y-3">
      <CadenceTextField id="widget-title" v-model="fields.title" label="Title" required />
      <CadenceChoiceField
        id="widget-type"
        v-model="fields.type"
        label="Visualization"
        :options="typeOptions"
      />
      <CadenceChoiceField
        id="widget-section"
        v-model="fields.section_id"
        label="Section"
        :options="sectionOptions"
      />
    </section>
    <section
      v-if="bindsObservables(fields.type)"
      class="space-y-3 border-t border-base-300/60 pt-4"
    >
      <WidgetBindingFields v-model="fields" :scope-options="scopeOptions" />
      <ObservableSearch v-model="selected" :fields="fields" :search="search" />
    </section>
    <section class="space-y-3 border-t border-base-300/60 pt-4">
      <span class="hud-label">Display</span>
      <WidgetDisplayFields v-model="fields" />
    </section>
    <footer class="flex items-center justify-end gap-2 border-t border-base-300/60 pt-4">
      <span v-if="missing" class="mr-auto text-xs text-warning">{{ missing }}</span>
      <CadenceButton variant="quiet" size="sm" @click="emit('cancel')">Cancel</CadenceButton>
      <CadenceButton
        type="submit"
        variant="primary"
        size="sm"
        :loading="pending"
        :disabled="!!missing"
      >
        {{ creating ? "Add widget" : "Apply" }}
      </CadenceButton>
    </footer>
  </form>
</template>
