<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApSegmented, ApSheet } from "@/ui";
import LibraryPicker from "../library/LibraryPicker.vue";
import {
  widgetDefaults,
  type Command,
  type OutlinePlacement,
  type WidgetFieldKey,
} from "./contracts.ts";
import { newId } from "./draft.ts";
import WidgetBindingFields from "./WidgetBindingFields.vue";
import WidgetDisplayFields from "./WidgetDisplayFields.vue";

/**
 * The widget sheet (ux: right side, 400px, non-modal so the grid stays usable). Edits a copy of
 * the widget's form; Apply stages one add_widget / update_widget command. Adding can instead pick
 * `From library` (fe-ops' LibraryPicker): a reference to the item's version (add_library_widget),
 * not a copy, so "Used in N dashboards" stays true.
 */
const props = defineProps<{
  missionId: string;
  dashboardId: string;
  baseVersion: number;
  sections: readonly { id: string; title: string }[];
  spacecraft: readonly { id: string; name: string }[];
}>();
const emit = defineEmits<{ stage: [command: Command] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const placementId = ref<string | null>(null);
const fields = ref<Record<WidgetFieldKey, string>>({ ...widgetDefaults });
const observables = ref<readonly string[]>([]);
const title = computed(() => (placementId.value ? "Edit widget" : "Add widget"));
const source = ref<"new" | "library">("new");
const sources = [
  { value: "new", label: "New widget" },
  { value: "library", label: "From library" },
];
const setSource = (v: string) => {
  if (v === "new" || v === "library") source.value = v;
};
const valid = computed(
  () =>
    fields.value.title.trim() !== "" &&
    (fields.value.mode !== "fixed" || fields.value.spacecraft_id !== ""),
);

function openFor(placement: OutlinePlacement | null, sectionId = "") {
  placementId.value = placement?.id ?? null;
  fields.value = {
    ...widgetDefaults,
    ...placement?.fields,
    ...(placement ? {} : { section_id: sectionId }),
  };
  observables.value = placement?.observables ?? [];
  source.value = "new";
  sheet.value?.open();
}
function apply() {
  const input = { fields: { ...fields.value }, observables: [...observables.value] };
  emit(
    "stage",
    placementId.value
      ? { event: "update_widget", input: { placement_id: placementId.value, ...input } }
      : { event: "add_widget", input: { placement_id: newId("dash_widget"), ...input } },
  );
  sheet.value?.close();
}
function pickLibrary(pick: { library_item_id: string; version: number }) {
  emit("stage", {
    event: "add_library_widget",
    input: {
      placement_id: newId("dash_widget"),
      library_item_id: pick.library_item_id,
      version: pick.version,
      section_id: fields.value.section_id,
    },
  });
  sheet.value?.close();
}
defineExpose({ openFor, close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet ref="sheet" :title="title" placement="side" initial-focus="input">
    <ApSegmented
      v-if="!placementId"
      class="mb-3"
      :model-value="source"
      label="Widget"
      :options="sources"
      @update:model-value="setSource"
    />
    <LibraryPicker v-if="source === 'library'" :mission-id="missionId" @pick="pickLibrary" />
    <div v-else class="flex flex-col gap-3">
      <WidgetBindingFields
        v-model:fields="fields"
        v-model:observables="observables"
        :mission-id="missionId"
        :dashboard-id="dashboardId"
        :base-version="baseVersion"
        :sections="sections"
        :spacecraft="spacecraft"
      />
      <WidgetDisplayFields v-model:fields="fields" />
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        v-if="source === 'new'"
        variant="primary"
        :disabled="!valid"
        disabled-reason="Give it a title (and a spacecraft when it's fixed to one)."
        @click="apply"
        >{{ placementId ? "Apply" : "Add widget" }}</ApButton
      >
    </template>
  </ApSheet>
</template>
