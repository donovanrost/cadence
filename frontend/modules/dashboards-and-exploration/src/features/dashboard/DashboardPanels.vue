<script setup lang="ts">
import { computed } from "vue";
import type { DashboardOutline, DetailsChange, SectionInput, WidgetInput } from "./contracts";
import type { DashboardPageState } from "./useDashboardPage";
import type { Panel } from "./panels";
import DetailsEditor from "./DetailsEditor.vue";
import EditSheet from "./EditSheet.vue";
import SectionEditor from "./SectionEditor.vue";
import WidgetEditor from "./WidgetEditor.vue";
import WidgetInspector from "./WidgetInspector.vue";

const props = defineProps<{ state: DashboardPageState; outline: DashboardOutline | null }>();
const panel = defineModel<Panel | null>({ required: true });
const close = () => (panel.value = null);

const placement = computed(() => {
  const current = panel.value;
  return current?.kind === "widget" && current.id
    ? (props.outline?.placements.find((p) => p.id === current.id) ?? null)
    : null;
});
const section = computed(() => {
  const current = panel.value;
  return current?.kind === "section" && current.id
    ? (props.outline?.sections.find((s) => s.id === current.id) ?? null)
    : null;
});
const title = computed(() => {
  switch (panel.value?.kind) {
    case "widget":
      return panel.value.id ? "Configure widget" : "Add widget";
    case "section":
      return panel.value.id ? "Edit section" : "Add section";
    case "details":
      return "Dashboard details";
    case "inspect":
      return `Inspect · ${panel.value.placement.widget?.title ?? panel.value.placement.authored_id}`;
    default:
      return "";
  }
});

async function applyWidget(input: WidgetInput) {
  const id = placement.value?.id;
  const ok = id
    ? await props.state.stage("update_widget", { ...input, placement_id: id })
    : await props.state.stage("add_widget", input);
  if (ok) close();
}
async function applySection(input: SectionInput) {
  const id = section.value?.id;
  const ok = id
    ? await props.state.stage("update_section", { ...input, section_id: id })
    : await props.state.stage("add_section", input);
  if (ok) close();
}
// Each staged change confirms before the next, so they apply in order.
async function applyDetails(change: DetailsChange) {
  if (change.rename && !(await props.state.stage("rename", change.rename))) return;
  if (change.defaults !== null)
    if (!(await props.state.stage("runtime_defaults", { defaults_json: change.defaults }))) return;
  close();
}
</script>

<template>
  <EditSheet
    v-if="panel"
    :title="title"
    :width="panel.kind === 'inspect' ? 'lg' : 'md'"
    @close="close"
  >
    <WidgetInspector v-if="panel.kind === 'inspect'" :placement="panel.placement" />
    <template v-else-if="outline">
      <WidgetEditor
        v-if="panel.kind === 'widget' && (placement?.fields || !panel.id)"
        :key="panel.id ?? 'new'"
        :initial="placement?.fields ?? outline.defaults"
        :observables="placement?.observables ?? []"
        :sections="outline.sections"
        :scope-options="state.page.value.scope_options"
        :creating="!panel.id"
        :pending="state.pending.value"
        :search="state.searchObservables"
        @apply="applyWidget"
        @cancel="close"
      />
      <p v-else-if="panel.kind === 'widget'" class="text-sm text-base-content/70">
        This widget comes from the widget library and is edited there.
      </p>
      <SectionEditor
        v-else-if="panel.kind === 'section'"
        :key="panel.id ?? 'new'"
        :initial="section ?? { title: '', description: '', collapsed_by_default: false }"
        :creating="!panel.id"
        :pending="state.pending.value"
        @apply="applySection"
        @cancel="close"
      />
      <DetailsEditor
        v-else-if="panel.kind === 'details'"
        :name="outline.name"
        :description="outline.description"
        :defaults-json="outline.runtime_defaults_json"
        :pending="state.pending.value"
        :settings-href="`${state.base.value}/settings`"
        @apply="applyDetails"
        @cancel="close"
      />
    </template>
  </EditSheet>
</template>
