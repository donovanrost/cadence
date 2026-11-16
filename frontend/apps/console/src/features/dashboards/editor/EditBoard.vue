<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { ApButton, ApCallout } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import type { Command, LayoutEdit, Outline, OutlinePlacement, Preview } from "./contracts.ts";
import EditSection from "./EditSection.vue";
import EditSectionHead from "./EditSectionHead.vue";
import { refocus } from "../focus-fallback.ts";

/**
 * The board in edit mode: sections of editable grids over the staged outline and preview. Once a
 * board has sections, its unsectioned widgets get a faint 'Not in a section' heading so widgets a
 * removed section left behind are findable; an empty section says so (ux, Sections in edit mode).
 */
const props = defineProps<{ preview: Preview }>();
const emit = defineEmits<{
  stage: [command: Command];
  edit: [p: OutlinePlacement | null, sectionId: string];
  editSection: [section: Outline["sections"][number]];
}>();
const previews = computed(() => {
  // A repeated widget previews through its first instance (they share the authored placement).
  const map = new Map<string, WorkspacePlacement>();
  for (const p of props.preview.snapshot.placements)
    if (!map.has(p.authored_id)) map.set(p.authored_id, p);
  return map;
});
const outline = computed(() => props.preview.outline);
const inSection = (id: string | null) =>
  outline.value.placements.filter((p) => p.section_id === id);
const loose = computed(() => inSection(null));
const sections = computed(() =>
  outline.value.sections.map((s) => ({ section: s, placements: inSection(s.id) })),
);
const empty = computed(() => outline.value.placements.length === 0);

/**
 * After 'Remove section', focus goes to the next section's heading, else the previous one's, else
 * Add section (ux a11y checklist). The section leaves only when the staged preview refreshes, so
 * the move waits until its heading is gone.
 */
const root = ref<HTMLElement | null>(null);
const pendingFocus = ref<{ removed: string; target: string | null } | null>(null);
function onSectionStage(command: Command, index: number) {
  if (command.event === "remove_section") {
    const list = sections.value;
    const target = list[index + 1]?.section.id ?? list[index - 1]?.section.id ?? null;
    pendingFocus.value = { removed: command.input.section_id, target };
  }
  emit("stage", command);
}
watch(
  () => sections.value.map((s) => s.section.id),
  async (ids) => {
    const pending = pendingFocus.value;
    if (!pending || ids.includes(pending.removed)) return;
    pendingFocus.value = null;
    await nextTick();
    const heading = pending.target
      ? root.value?.querySelector<HTMLElement>(`[data-section-heading="${pending.target}"]`)
      : null;
    (heading ?? document.querySelector<HTMLElement>("[data-add-section]"))?.focus();
  },
);
const onLayout = (layouts: LayoutEdit[]) => emit("stage", { event: "layout", input: { layouts } });
/** A removed widget took its focused Remove button: its section's heading, else Add widget (A5). */
const removedWidget = ref<OutlinePlacement | null>(null);
function onRemove(p: OutlinePlacement) {
  removedWidget.value = p;
  emit("stage", { event: "remove_widget", input: { placement_id: p.id } });
}
watch(
  () => outline.value.placements.map((p) => p.id),
  async (ids) => {
    const p = removedWidget.value;
    if (!p || ids.includes(p.id)) return;
    removedWidget.value = null;
    await nextTick();
    const heading = p.section_id
      ? root.value?.querySelector<HTMLElement>(`[data-section-heading="${p.section_id}"]`)
      : null;
    refocus(heading ?? document.querySelector<HTMLElement>("[data-add-widget]"));
  },
);
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
  <div ref="root" class="flex flex-col gap-3">
    <section v-if="loose.length || !sections.length" class="flex flex-col gap-2">
      <h2 v-if="sections.length" class="m-0 font-display text-sm uppercase text-text-4">
        Not in a section
      </h2>
      <EditSection
        :placements="loose"
        :previews="previews"
        :snapshot="preview.snapshot"
        @layout="onLayout"
        @edit="emit('edit', $event, '')"
        @remove="onRemove"
      />
    </section>
    <section v-for="(s, i) in sections" :key="s.section.id" class="flex flex-col gap-2">
      <EditSectionHead
        :section="s.section"
        :count="s.placements.length"
        :first="i === 0"
        :last="i === sections.length - 1"
        @add-widget="emit('edit', null, s.section.id)"
        @edit="emit('editSection', s.section)"
        @stage="onSectionStage($event, i)"
      />
      <p v-if="!s.placements.length" class="m-0 text-sm text-text-3">No widgets yet.</p>
      <EditSection
        v-else
        :placements="s.placements"
        :previews="previews"
        :snapshot="preview.snapshot"
        @layout="onLayout"
        @edit="emit('edit', $event, s.section.id)"
        @remove="onRemove"
      />
    </section>
  </div>
</template>
