<script setup lang="ts">
import { SplitterGroup } from "reka-ui";
const props = withDefaults(
  defineProps<{
    id: string;
    direction?: "horizontal" | "vertical";
    autoSaveId?: string;
    keyboardResizeBy?: number;
  }>(),
  { direction: "horizontal", keyboardResizeBy: 5 },
);
const emit = defineEmits<{ layout: [sizes: number[]] }>();
</script>

<template>
  <SplitterGroup
    :id="props.id"
    :direction="props.direction"
    :auto-save-id="props.autoSaveId ?? null"
    :keyboard-resize-by="props.keyboardResizeBy"
    class="cadence-splitter-group"
    @layout="emit('layout', $event)"
  >
    <slot />
  </SplitterGroup>
</template>

<style scoped>
.cadence-splitter-group {
  min-width: 0;
  min-height: 0;
}
</style>
