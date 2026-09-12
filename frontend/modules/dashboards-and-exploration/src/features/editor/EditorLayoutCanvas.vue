<script setup lang="ts">
import { computed, provide } from "vue";
import type { EditorModel } from "./contracts";
import { mergeLayoutEdits, type LayoutEdit } from "./layout-draft";
import EditorLayoutGrid from "./EditorLayoutGrid.vue";
import DashboardWidget from "../workspace/DashboardWidget.vue";
import { snapshotPresentation } from "../workspace/snapshot-presentation";
import { CHART_RUNTIME_PORT } from "../workspace/chart-runtime";
const props = defineProps<{
  model: EditorModel;
  modelValue: LayoutEdit[];
  disabled: boolean;
  instanceId: string;
}>();
const emit = defineEmits<{
  "update:modelValue": [value: LayoutEdit[]];
  gesture: [active: boolean];
}>();
provide(CHART_RUNTIME_PORT, { version: 1, execute() {}, subscribe: () => () => {} });
const groups = computed(() =>
  [
    ...props.model.sections.map((s) => ({ id: s.id, title: s.title })),
    { id: null, title: "Unsectioned" },
  ]
    .map((group) => ({
      ...group,
      placements: props.model.placements.filter((p) => p.section_id === group.id),
    }))
    .filter((g) => g.placements.length),
);
const previews = computed(() => {
  const result = new Map<string, any>();
  if (props.model.preview) {
    const presentation = snapshotPresentation(props.model.preview, `${props.instanceId}-layout`);
    for (const group of presentation.groups)
      for (const widget of group.grid.widgets) {
        const id = widget.shell.attrs["gs-id"];
        const placement = props.model.preview.placements.find((p) => p.id === id);
        if (placement && !result.has(placement.authored_id))
          result.set(placement.authored_id, widget.presentation);
      }
  }
  return result;
});
</script>
<template>
  <section
    id="editor-layout-canvas"
    class="space-y-4 min-w-0"
    aria-label="Arrange dashboard widgets"
  >
    <p class="text-xs text-base-content/65">
      Drag a title to move a widget; drag its lower edge or corner to resize. Arrow keys on Move and
      Resize controls provide the same operations. Each section has its own grid. Previews show the
      staged candidate; apply layout edits to the candidate before switching panels.
    </p>
    <section
      v-for="group in groups"
      :key="JSON.stringify([group.id])"
      class="min-w-0 border border-base-300 p-3"
    >
      <h3 class="font-mono text-xs uppercase tracking-wider mb-3">{{ group.title }}</h3>
      <EditorLayoutGrid
        :key="`${model.document_version}:${group.id}`"
        :placements="group.placements"
        :edits="modelValue"
        :grid="model.grid"
        :disabled="disabled"
        @change="emit('update:modelValue', mergeLayoutEdits(modelValue, $event))"
        @gesture="emit('gesture', $event)"
      >
        <template #default="{ placement }"
          ><DashboardWidget
            v-if="previews.has(placement.id)"
            :presentation="previews.get(placement.id)"
          />
          <p v-else class="text-xs text-base-content/60 p-2">
            {{ placement.title }}<br />Candidate widget preview unavailable
          </p></template
        >
      </EditorLayoutGrid>
    </section>
    <p v-if="!groups.length" class="text-sm text-base-content/60">
      Add a widget before arranging the dashboard.
    </p>
  </section>
</template>
