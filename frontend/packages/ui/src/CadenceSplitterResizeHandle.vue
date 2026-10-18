<script setup lang="ts">
import { SplitterResizeHandle } from "reka-ui";
withDefaults(defineProps<{ id: string; label: string; disabled?: boolean }>(), { disabled: false });
const emit = defineEmits<{ dragging: [active: boolean] }>();
// Replacing this object re-registers the Reka handle and loses the active drag's release.
const hitAreaMargins = { coarse: 12, fine: 4 };
</script>

<template>
  <SplitterResizeHandle
    :id="id"
    :aria-label="label"
    :disabled="disabled"
    class="cadence-splitter-handle"
    :hit-area-margins="hitAreaMargins"
    @dragging="emit('dragging', $event)"
  >
    <span aria-hidden="true" class="cadence-splitter-handle__grip" />
  </SplitterResizeHandle>
</template>

<style scoped>
.cadence-splitter-handle {
  position: relative;
  display: flex;
  flex: none;
  align-items: center;
  justify-content: center;
  background: var(--surface-inset);
  touch-action: none;
}
.cadence-splitter-handle[data-orientation="horizontal"] {
  width: 8px;
  cursor: col-resize;
}
.cadence-splitter-handle[data-orientation="vertical"] {
  height: 8px;
  cursor: row-resize;
}
.cadence-splitter-handle__grip {
  border-radius: var(--radius-sm);
  background: var(--border-default);
}
[data-orientation="horizontal"] > .cadence-splitter-handle__grip {
  width: 2px;
  height: 28px;
}
[data-orientation="vertical"] > .cadence-splitter-handle__grip {
  height: 2px;
  width: 28px;
}
.cadence-splitter-handle:hover > span,
.cadence-splitter-handle[data-state="drag"] > span,
.cadence-splitter-handle:focus-visible > span {
  background: var(--color-action);
}
.cadence-splitter-handle:focus-visible {
  outline: 2px solid var(--color-action);
  outline-offset: -2px;
}
.cadence-splitter-handle[data-disabled] {
  opacity: 0.4;
  cursor: default;
}
</style>
