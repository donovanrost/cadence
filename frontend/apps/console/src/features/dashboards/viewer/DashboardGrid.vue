<script setup lang="ts">
import { computed, ref, useId, watch } from "vue";
import { useNow } from "@/ui";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import SectionHeading from "./SectionHeading.vue";
import { readingOrder } from "../model/widget-data.ts";
import WidgetPanel from "./WidgetPanel.vue";

/**
 * Read-only board: each section is a CSS grid on the document's columns and row height, with the
 * 12px gutter (ux). Placements without a position flow in order. Phone (< 768): one column in
 * grid order. Editing (slice 3) swaps in GridStack; viewing never needs it. A titled section
 * opens or starts collapsed per its default; a viewer's toggle isn't saved, so kiosk and Present
 * (fresh mounts) show the default. Empty sections aren't drawn (ux, Sections in the viewer).
 */
const props = defineProps<{ snapshot: WorkspaceSnapshot }>();
const emit = defineEmits<{ inspect: [placement: WorkspacePlacement] }>();
const now = useNow();
const sections = computed(() => {
  const groups = [
    {
      id: null as string | null,
      title: null as string | null,
      description: null,
      collapsed: false,
    },
    ...props.snapshot.sections,
  ].map((s) => ({
    ...s,
    placements: props.snapshot.placements
      .filter((p) => p.section_id === s.id)
      .slice()
      .sort((a, b) => readingOrder(a) - readingOrder(b)),
  }));
  return groups.filter((g) => g.placements.length > 0);
});
/** A viewer's own toggles, by section id; unset means the section's default. Not saved. */
const toggled = ref(new Map<string, boolean>());
watch(
  () => props.snapshot.dashboard_id,
  () => (toggled.value = new Map()),
);
const isOpen = (s: { id: string | null; collapsed: boolean }) =>
  s.id === null || (toggled.value.get(s.id) ?? !s.collapsed);
function toggle(s: { id: string | null; collapsed: boolean }) {
  if (s.id !== null) toggled.value = new Map(toggled.value).set(s.id, !isOpen(s));
}
const bodyPrefix = useId();
const gridStyle = computed(() => ({
  "--cols": String(props.snapshot.grid.columns),
  "--row": `${props.snapshot.grid.row_height_px}px`,
}));
const cell = (p: WorkspacePlacement) => ({
  "--col": p.layout.x === null ? `span ${p.layout.w}` : `${p.layout.x + 1} / span ${p.layout.w}`,
  "--rows": p.layout.y === null ? `span ${p.layout.h}` : `${p.layout.y + 1} / span ${p.layout.h}`,
});
</script>

<template>
  <div class="flex flex-col gap-3" :style="gridStyle">
    <section v-for="s in sections" :key="s.id ?? 'top'" class="flex flex-col gap-2">
      <SectionHeading
        v-if="s.title"
        :title="s.title"
        :description="s.description"
        :count="s.placements.length"
        :open="isOpen(s)"
        :body-id="`${bodyPrefix}-${s.id}`"
        @toggle="toggle(s)"
      />
      <div
        v-show="isOpen(s)"
        :id="`${bodyPrefix}-${s.id ?? 'top'}`"
        class="grid grid-cols-1 gap-3 md:grid-cols-[repeat(var(--cols),minmax(0,1fr))] md:auto-rows-[var(--row)]"
      >
        <div
          v-for="(p, i) in s.placements"
          :key="p.id"
          class="min-h-[240px] md:min-h-0 md:[grid-column:var(--col)] md:[grid-row:var(--rows)]"
          :style="cell(p)"
        >
          <WidgetPanel
            :placement="p"
            :position="i + 1"
            :context="snapshot.context"
            :now="now.getTime()"
            :group="snapshot.dashboard_id"
            @inspect="emit('inspect', $event)"
          />
        </div>
      </div>
    </section>
  </div>
</template>
