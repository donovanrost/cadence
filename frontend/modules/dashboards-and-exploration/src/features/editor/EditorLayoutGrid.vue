<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { GridStack } from "gridstack";
import "../../workspace.css";
import { layoutEdits } from "./layout-draft";
const props = defineProps({
  placements: {
    type: /** @type {import("vue").PropType<import("./contracts").EditorPlacement[]>} */ (Array),
    required: true,
  },
  edits: {
    type: /** @type {import("vue").PropType<import("./layout-draft").LayoutEdit[]>} */ (Array),
    required: true,
  },
  grid: {
    type: /** @type {import("vue").PropType<import("./contracts").EditorModel["grid"]>} */ (Object),
    required: true,
  },
  disabled: Boolean,
});
const emit = defineEmits(["change", "gesture"]);
const element = ref(null),
  notice = ref("");
let grid,
  active = false,
  disposed = false,
  epoch = 0;
function nodes() {
  return props.placements.map((p) => {
    const layout = props.edits.find((edit) => edit.placement_id === p.id) || p.layout;
    return {
      id: p.id,
      ...layout,
      x: layout.x ?? undefined,
      y: layout.y ?? undefined,
      autoPosition: layout.x === null || layout.y === null,
      minW: p.constraints.min_w,
      minH: p.constraints.min_h,
      maxW: p.constraints.max_w,
      maxH: p.constraints.max_h,
    };
  });
}
function sync() {
  if (disposed || !grid || active) return;
  grid.load(nodes(), false);
  grid.setStatic(props.disabled);
}
function publish() {
  if (disposed || props.disabled) return;
  try {
    const edits = layoutEdits(grid.engine.nodes, props.placements);
    notice.value =
      "Layout updated locally. Apply it to the candidate, then Save draft to persist it.";
    emit("change", edits);
  } catch {
    notice.value =
      "That layout exceeds the supported grid bounds. The last local layout was restored.";
    sync();
  }
}
function start() {
  if (!props.disabled) {
    active = true;
    emit("gesture", true);
  }
}
function stop() {
  const captured = epoch;
  active = false;
  // GridStack completes neighbor reflow after dragstop/resizestop dispatch.
  queueMicrotask(async () => {
    await nextTick();
    if (disposed || captured !== epoch) return;
    publish();
    emit("gesture", false);
  });
}
function keyboard(event, id, resize) {
  const delta = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[
    event.key
  ];
  if (!delta || props.disabled || active) return;
  event.preventDefault();
  const node = grid.engine.nodes.find((n) => n.id === id);
  const bounds = props.placements.find((p) => p.id === id).constraints;
  const change = resize
    ? {
        w: Math.max(bounds.min_w, Math.min(bounds.max_w - node.x, node.w + delta[0])),
        h: Math.max(bounds.min_h, Math.min(bounds.max_h, node.h + delta[1])),
      }
    : {
        x: Math.max(0, Math.min(bounds.max_w - node.w, node.x + delta[0])),
        y: Math.max(0, Math.min(bounds.max_y, node.y + delta[1])),
      };
  grid.update(node.el, change);
  publish();
}
onMounted(() => {
  grid = GridStack.init(
    {
      column: props.grid.columns,
      cellHeight: props.grid.row_height_px,
      margin: props.grid.gap_px,
      float: true,
      staticGrid: true,
      animate: false,
      styleInHead: true,
      alwaysShowResizeHandle: true,
      handle: ".editor-layout-move",
      resizable: { handles: "e,se,s" },
      columnOpts: { breakpoints: [] },
    },
    element.value,
  );
  sync();
  grid.on("dragstart resizestart", start);
  grid.on("dragstop resizestop", stop);
});
watch(() => props.edits, sync, { deep: true, flush: "post" });
watch(
  () => props.disabled,
  () => {
    epoch++;
    active = false;
    emit("gesture", false);
    sync();
  },
);
onBeforeUnmount(() => {
  disposed = true;
  epoch++;
  grid?.destroy(false);
  emit("gesture", false);
});
</script>
<template>
  <div class="editor-grid-scroll">
    <div
      ref="element"
      class="grid-stack editor-authoring-grid"
      :style="{
        minWidth: `${props.grid.columns * 48}px`,
        backgroundSize: `${100 / props.grid.columns}% ${props.grid.row_height_px}px`,
      }"
    >
      <div
        v-for="placement in placements"
        :key="placement.id"
        class="grid-stack-item"
        :gs-id="placement.id"
        :gs-x="placement.layout.x"
        :gs-y="placement.layout.y"
        :gs-w="placement.layout.w"
        :gs-h="placement.layout.h"
      >
        <div class="grid-stack-item-content editor-layout-card">
          <button
            type="button"
            class="editor-layout-move"
            :disabled="disabled"
            :data-layout-move="placement.id"
            :aria-label="`Move ${placement.title}; use arrow keys`"
            @keydown="keyboard($event, placement.id, false)"
          >
            {{ placement.title }} <span aria-hidden="true">⠿</span>
          </button>
          <div class="editor-layout-body">
            <slot :placement="placement"
              ><span class="text-xs text-base-content/60"
                >Candidate widget preview unavailable</span
              ></slot
            >
          </div>
          <button
            type="button"
            class="editor-layout-keyboard"
            :disabled="disabled"
            :data-layout-resize="placement.id"
            :aria-label="`Resize ${placement.title}; use arrow keys`"
            @keydown="keyboard($event, placement.id, true)"
          >
            Resize with arrow keys
          </button>
        </div>
      </div>
    </div>
  </div>
  <p v-if="notice" role="status" class="text-xs text-base-content/65 mt-2">{{ notice }}</p>
</template>
<style scoped>
.editor-grid-scroll {
  overflow-x: auto;
  max-width: 100%;
}
.editor-authoring-grid {
  min-height: 180px;
  background:
    linear-gradient(90deg, #42cde810 1px, transparent 1px),
    linear-gradient(#42cde810 1px, transparent 1px);
}
.editor-layout-card {
  border: 1px solid var(--color-base-300, #283440);
  border-radius: 4px;
  background: var(--color-base-200, #081018);
  display: flex;
  flex-direction: column;
}
.editor-layout-move {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
  padding: 8px;
  text-align: left;
  font-size: 12px;
  cursor: grab;
  touch-action: none;
  border-bottom: 1px solid var(--color-base-300, #283440);
}
.editor-layout-move:focus-visible,
.editor-layout-keyboard:focus-visible {
  outline: 2px solid #42cde8;
  outline-offset: -2px;
}
.editor-layout-body {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  padding: 4px;
}
.editor-layout-keyboard {
  align-self: flex-start;
  font-size: 10px;
  padding: 2px 8px;
  color: #a6bdc8;
}
</style>
