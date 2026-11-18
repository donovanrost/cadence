<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApInlineConfirm } from "@/ui";
import MoreMenu from "../viewer/MoreMenu.vue";
import type { Command, Outline } from "./contracts.ts";

/**
 * A section's heading in edit mode (ux Dashboards.md › Grid › 'Sections in edit mode'): Add widget
 * here, Edit, and ⋯ Move up / Move down / Remove section…. Removing keeps the widgets (the server
 * moves them out to the top, unsectioned area), so a non-empty section confirms in place first.
 */
type Section = Outline["sections"][number];
type Action = "up" | "down" | "remove";
const props = defineProps<{ section: Section; count: number; first: boolean; last: boolean }>();
const emit = defineEmits<{ addWidget: []; edit: []; stage: [command: Command] }>();
const confirming = ref(false);
/** B7: the heading's buttons name their section. */
const name = computed(() => props.section.title || "Untitled section");
const items = computed(() => [
  {
    id: "up" as const,
    label: "Move up",
    disabled: props.first ? "It's already first." : undefined,
  },
  {
    id: "down" as const,
    label: "Move down",
    disabled: props.last ? "It's already last." : undefined,
  },
  { id: "remove" as const, label: "Remove section…" },
]);
const widgets = computed(() =>
  props.count === 1 ? "1 widget stays" : `${props.count} widgets stay`,
);

/**
 * Remove section… on a non-empty section opens the kit's in-place confirm (design-language §7):
 * it opens on Cancel, Esc backs out, and focus returns to the ⋯ that opened it.
 */
function onMenu(id: Action) {
  const section_id = props.section.id;
  if (id !== "remove")
    emit("stage", { event: "move_section", input: { section_id, direction: id } });
  else if (props.count === 0) emit("stage", { event: "remove_section", input: { section_id } });
  else confirming.value = true;
}
function remove() {
  confirming.value = false;
  emit("stage", { event: "remove_section", input: { section_id: props.section.id } });
}
</script>

<template>
  <header class="flex flex-col gap-1">
    <div class="flex items-center gap-2">
      <!-- tabindex -1: focus lands here when the section above it is removed (ux a11y). -->
      <h2
        tabindex="-1"
        :data-section-heading="section.id"
        class="m-0 mr-auto font-display text-sm uppercase tracking-title text-text-2"
      >
        {{ section.title }}
      </h2>
      <ApButton
        variant="ghost"
        size="compact"
        :aria-label="`Add widget here, in ${name}`"
        @click="emit('addWidget')"
        >Add widget here</ApButton
      >
      <ApButton
        variant="ghost"
        size="compact"
        :aria-label="`Edit section ${name}`"
        @click="emit('edit')"
        >Edit</ApButton
      >
      <MoreMenu :items="items" :label="`More actions for section ${name}`" @select="onMenu" />
    </div>
    <p v-if="section.description" class="m-0 line-clamp-2 text-sm text-text-3">
      {{ section.description }}
    </p>
    <ApInlineConfirm v-model:open="confirming" action="Remove section" @confirm="remove">
      Remove the section “{{ section.title }}”? Its {{ widgets }} on the dashboard, at the top,
      outside any section.
    </ApInlineConfirm>
  </header>
</template>
