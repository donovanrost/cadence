<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, onUpdated, ref } from "vue";
import { ApButton, ApPanel } from "@/ui";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import WidgetBody from "../widgets/WidgetBody.vue";
import { BoardGrid } from "./board-grid.ts";
import { keyboardLayout, positionText } from "./keyboard-layout.ts";
import type { LayoutEdit, OutlinePlacement } from "./contracts.ts";
import "./editor.css";

/**
 * One section's grid while editing: GridStack owns drag and resize; layout edits come back
 * debounced (one per gesture). Bodies show the staged preview with live values paused.
 */
const props = defineProps<{
  placements: readonly OutlinePlacement[];
  previews: ReadonlyMap<string, WorkspacePlacement>;
  snapshot: WorkspaceSnapshot;
}>();
const emit = defineEmits<{
  layout: [layouts: LayoutEdit[]];
  edit: [p: OutlinePlacement];
  remove: [p: OutlinePlacement];
}>();
const el = ref<HTMLElement | null>(null);
let grid: BoardGrid | null = null;
onMounted(() => {
  if (el.value)
    grid = new BoardGrid(el.value, { ...props.snapshot.grid, gap_px: 6 }, true, (layouts) =>
      emit("layout", layouts),
    );
});
onUpdated(() => grid?.reconcile());
onBeforeUnmount(() => {
  grid?.destroy();
  grid = null;
});
const items = computed(() =>
  props.placements.map((p) => ({ p, preview: props.previews.get(p.id) ?? null })),
);
const at = (v: number | null) => (v === null ? undefined : String(v));
/** Spoken after a keyboard move or resize (qa: screen readers heard nothing). */
const announcement = ref("");
function onHandleKey(p: OutlinePlacement, event: KeyboardEvent) {
  const edit = keyboardLayout(p, event.key, event.shiftKey, props.snapshot.grid.columns);
  if (!edit) return;
  event.preventDefault();
  emit("layout", [edit]);
  announcement.value = `${nameOf(p)}: ${positionText(edit)}.`;
}
/** B7: an untitled widget's controls still name what they act on. */
const nameOf = (p: OutlinePlacement) => p.title || "Untitled widget";
</script>

<template>
  <p class="sr-only" aria-live="polite">{{ announcement }}</p>
  <div ref="el" class="grid-stack dashboard-edit-grid">
    <div
      v-for="{ p, preview } in items"
      :key="p.id"
      class="grid-stack-item"
      :gs-id="p.id"
      :gs-x="at(p.layout.x)"
      :gs-y="at(p.layout.y)"
      :gs-w="String(p.layout.w)"
      :gs-h="String(p.layout.h)"
      :gs-min-w="String(p.constraints.min_w)"
      :gs-min-h="String(p.constraints.min_h)"
      :gs-max-w="String(p.constraints.max_w)"
      :gs-max-h="String(p.constraints.max_h)"
    >
      <div class="grid-stack-item-content">
        <ApPanel :title="nameOf(p)" :heading-level="3" flush pane class="h-full">
          <template #meta>
            <span class="flex items-center gap-1">
              <button
                type="button"
                data-drag-handle
                class="cursor-move border-0 bg-transparent px-1 font-mono text-text-4"
                :aria-label="`Move ${nameOf(p)}`"
                :aria-description="positionText(p.layout)"
                :data-layout="`${p.layout.x ?? ''},${p.layout.y ?? ''},${p.layout.w},${p.layout.h}`"
                aria-keyshortcuts="ArrowUp ArrowDown ArrowLeft ArrowRight Shift+ArrowUp Shift+ArrowDown Shift+ArrowLeft Shift+ArrowRight"
                title="Drag to move. Arrow keys move; Shift+arrow keys resize."
                @keydown="onHandleKey(p, $event)"
              >
                ⠿
              </button>
              <ApButton
                v-if="p.editable"
                variant="ghost"
                size="compact"
                :aria-label="`Edit ${nameOf(p)}`"
                @click="emit('edit', p)"
                >Edit</ApButton
              >
              <ApButton
                variant="ghost"
                size="compact"
                :aria-label="`Remove ${nameOf(p)}`"
                @click="emit('remove', p)"
                >Remove</ApButton
              >
            </span>
          </template>
          <WidgetBody
            v-if="preview"
            :placement="preview"
            :context="snapshot.context"
            :now="Date.now()"
            :group="`edit-${snapshot.dashboard_id}`"
            :chart-id="`edit-chart-${p.id}`"
          />
          <p v-else class="m-auto text-sm text-text-3">Preview after the next refresh.</p>
        </ApPanel>
      </div>
    </div>
  </div>
</template>
