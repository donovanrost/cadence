<script setup lang="ts">
import { computed } from "vue";
import { ApPanel } from "@/ui";
import type { Outline } from "../editor/contracts.ts";

/** A definition-only share (ux): the layout and titles, and in each widget why there's no data. */
const props = defineProps<{ definition: Outline }>();
const sections = computed(() =>
  [{ id: null as string | null, title: null as string | null }, ...props.definition.sections]
    .map((s) => ({
      ...s,
      placements: props.definition.placements.filter((p) => p.section_id === s.id),
    }))
    .filter((s) => s.placements.length > 0),
);
const cell = (l: Outline["placements"][number]["layout"]) => ({
  "--col": l.x === null ? `span ${l.w}` : `${l.x + 1} / span ${l.w}`,
  "--rows": l.y === null ? `span ${l.h}` : `${l.y + 1} / span ${l.h}`,
});
</script>

<template>
  <div
    class="flex flex-col gap-3"
    :style="{
      '--cols': String(definition.grid.columns),
      '--row': `${definition.grid.row_height_px}px`,
    }"
  >
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
          class="min-h-[160px] md:min-h-0 md:[grid-column:var(--col)] md:[grid-row:var(--rows)]"
          :style="cell(p.layout)"
        >
          <ApPanel :title="p.title" :heading-level="3" class="h-full">
            <p class="m-0 text-sm text-text-3">Data isn't shared in this link.</p>
          </ApPanel>
        </div>
      </div>
    </section>
  </div>
</template>
