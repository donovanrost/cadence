<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import type { Command, LayoutEdit, OutlinePlacement, Preview } from "./contracts.ts";
import EditSection from "./EditSection.vue";

/** The board in edit mode: sections of editable grids over the staged outline and preview. */
const props = defineProps<{ preview: Preview }>();
const emit = defineEmits<{
  stage: [command: Command];
  edit: [p: OutlinePlacement | null, sectionId: string];
}>();
const previews = computed(() => {
  // A repeated widget previews through its first instance (they share the authored placement).
  const map = new Map<string, WorkspacePlacement>();
  for (const p of props.preview.snapshot.placements)
    if (!map.has(p.authored_id)) map.set(p.authored_id, p);
  return map;
});
const sections = computed(() =>
  [
    { id: null as string | null, title: null as string | null },
    ...props.preview.outline.sections,
  ].map((s) => ({
    ...s,
    placements: props.preview.outline.placements.filter((p) => p.section_id === s.id),
  })),
);
const empty = computed(() => props.preview.outline.placements.length === 0);
const onLayout = (layouts: LayoutEdit[]) => emit("stage", { event: "layout", input: { layouts } });
const onRemove = (p: OutlinePlacement) =>
  emit("stage", { event: "remove_widget", input: { placement_id: p.id } });
</script>

<template>
  <ApCallout v-if="empty" tone="info">
    Add a widget to start.
    <template #action
      ><ApButton variant="primary" size="compact" @click="emit('edit', null, '')"
        >Add widget</ApButton
      ></template
    >
  </ApCallout>
  <div class="flex flex-col gap-3">
    <section v-for="s in sections" :key="s.id ?? 'top'" class="flex flex-col gap-2">
      <header v-if="s.title" class="flex items-center justify-between">
        <h2 class="m-0 font-display text-sm uppercase tracking-title text-text-2">{{ s.title }}</h2>
        <ApButton variant="ghost" size="compact" @click="emit('edit', null, s.id ?? '')"
          >Add widget here</ApButton
        >
      </header>
      <EditSection
        :placements="s.placements"
        :previews="previews"
        :snapshot="preview.snapshot"
        @layout="onLayout"
        @edit="emit('edit', $event, s.id ?? '')"
        @remove="onRemove"
      />
    </section>
  </div>
</template>
