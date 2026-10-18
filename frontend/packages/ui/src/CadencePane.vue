<script setup lang="ts">
import { ref } from "vue";
defineProps<{ id: string; title: string; icon?: string; count?: string | number }>();
const scrollElement = ref<HTMLElement | null>(null);
function scrollToStart() {
  if (scrollElement.value) scrollElement.value.scrollTop = 0;
}
defineExpose({ scrollElement, scrollToStart });
</script>
<template>
  <section class="cadence-pane" :aria-labelledby="`${id}-title`">
    <header class="cadence-pane__header">
      <h2 :id="`${id}-title`">
        <span v-if="icon" :class="icon" aria-hidden="true" /><slot name="title">{{ title }}</slot>
        <span v-if="count !== undefined" class="cadence-pane__count">{{ count }}</span>
      </h2>
      <div v-if="$slots.actions" class="cadence-pane__actions"><slot name="actions" /></div>
    </header>
    <div v-if="$slots.toolbar" class="cadence-pane__toolbar"><slot name="toolbar" /></div>
    <div ref="scrollElement" class="cadence-pane__body"><slot /></div>
    <footer v-if="$slots.footer" class="cadence-pane__footer"><slot name="footer" /></footer>
  </section>
</template>
<style scoped>
.cadence-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--border-subtle);
  border-radius: 3px;
  background: var(--surface-raised);
}
.cadence-pane__header {
  display: flex;
  flex-wrap: wrap;
  flex: none;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: calc(8 * var(--workspace-space, 4px) + 11px);
  padding: calc(1.75 * var(--workspace-space, 4px)) calc(3 * var(--workspace-space, 4px));
  border-bottom: 1px solid var(--border-subtle);
  background: var(--pane-header-background, transparent);
}
.cadence-pane__header h2 {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  max-width: 100%;
  margin: 0;
  font-size: 12px;
  font-weight: 650;
}
.cadence-pane__header h2 > span:first-child:not(.cadence-pane__count) {
  width: 16px;
  height: 16px;
  flex: none;
  color: var(--text-subtle);
}
.cadence-pane__count {
  font: 10px var(--font-mono);
  color: var(--text-subtle);
  border: 1px solid var(--border-default);
  border-radius: 3px;
  padding: 1px 5px;
  white-space: nowrap;
}
.cadence-pane__actions {
  display: flex;
  margin-inline-start: auto;
  align-items: center;
  gap: 6px;
}
.cadence-pane__toolbar {
  flex: none;
  border-bottom: 1px solid var(--border-subtle);
}
.cadence-pane__body {
  flex: 1;
  min-height: 0;
  min-width: 0;
  overflow: auto;
  overscroll-behavior: contain;
}
.cadence-pane__footer {
  display: flex;
  flex: none;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px;
  min-height: calc(6 * var(--workspace-space, 4px) + 6px);
  padding: calc(1.5 * var(--workspace-space, 4px)) calc(3 * var(--workspace-space, 4px));
  border-top: 1px solid var(--border-subtle);
  font-size: 10px;
  color: var(--text-subtle);
}
</style>
