<script setup lang="ts">
import { computed } from "vue";
import { useNow } from "@/ui";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import WidgetPanel from "./WidgetPanel.vue";

/**
 * Read-only board: each section is a CSS grid on the document's columns and row height, with the
 * 12px gutter (ux). Placements without a position flow in order. Phone (< 768): one column in
 * grid order. Editing (slice 3) swaps in GridStack; viewing never needs it.
 */
const props = defineProps<{ snapshot: WorkspaceSnapshot }>();
const emit = defineEmits<{ inspect: [placement: WorkspacePlacement] }>();
const now = useNow();
const order = (p: WorkspacePlacement) => (p.layout.y ?? 1e6) * 1000 + (p.layout.x ?? 0);
const sections = computed(() => {
  const groups = [
    { id: null as string | null, title: null as string | null },
    ...props.snapshot.sections.map((s) => ({ id: s.id, title: s.title })),
  ].map((s) => ({
    ...s,
    placements: props.snapshot.placements
      .filter((p) => p.section_id === s.id)
      .slice()
      .sort((a, b) => order(a) - order(b)),
  }));
  return groups.filter((g) => g.placements.length > 0);
});
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
      <h2 v-if="s.title" class="m-0 font-display text-sm uppercase tracking-title text-text-2">
        {{ s.title }}
      </h2>
      <div
        class="grid grid-cols-1 gap-3 md:grid-cols-[repeat(var(--cols),minmax(0,1fr))] md:auto-rows-[var(--row)]"
      >
        <div
          v-for="p in s.placements"
          :key="p.id"
          class="min-h-[240px] md:min-h-0 md:[grid-column:var(--col)] md:[grid-row:var(--rows)]"
          :style="cell(p)"
        >
          <WidgetPanel
            :placement="p"
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
