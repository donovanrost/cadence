<script setup lang="ts">
import { onBeforeUnmount, onMounted, onUpdated, ref, watch } from "vue";
import "../../workspace.css";
import type { WorkspacePlacement } from "../workspace/contracts";
import type { LayoutEdit } from "./contracts";
import { BoardGrid, type GridGeometry } from "./board-grid";

const props = defineProps<{
  placements: readonly WorkspacePlacement[];
  geometry: GridGeometry;
  editing: boolean;
  open: boolean;
}>();
const emit = defineEmits<{ layout: [layouts: LayoutEdit[]] }>();
defineSlots<{ default(props: { placement: WorkspacePlacement }): unknown }>();

const root = ref<HTMLElement | null>(null);
let grid: BoardGrid | null = null;
onMounted(() => {
  if (root.value)
    grid = new BoardGrid(root.value, props.geometry, props.editing, (layouts) =>
      emit("layout", layouts),
    );
});
onUpdated(() => grid?.reconcile());
watch(
  () => props.open,
  (open) => {
    if (open) grid?.remeasure();
  },
  { flush: "post" },
);
onBeforeUnmount(() => {
  grid?.destroy();
  grid = null;
});
const position = (p: WorkspacePlacement) => ({
  ...(p.layout.x === null ? {} : { "gs-x": String(p.layout.x) }),
  ...(p.layout.y === null ? {} : { "gs-y": String(p.layout.y) }),
  "gs-w": String(p.layout.w),
  "gs-h": String(p.layout.h),
});
</script>

<template>
  <div
    ref="root"
    class="grid-stack"
    :class="{ 'grid-stack-static': !editing }"
    :data-edit-mode="String(editing)"
  >
    <div
      v-for="placement in placements"
      :key="placement.id"
      class="grid-stack-item"
      :gs-id="placement.authored_id"
      v-bind="position(placement)"
    >
      <div class="grid-stack-item-content cadence-dashboard-panel">
        <slot :placement="placement" />
      </div>
    </div>
  </div>
</template>
