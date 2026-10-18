<script setup lang="ts">
defineProps<{ label: string }>();
</script>
<template>
  <div class="cadence-resource-navigation">
    <nav :aria-label="label"><slot /></nav>
    <div v-if="$slots.status" class="cadence-resource-navigation__status">
      <slot name="status" />
    </div>
  </div>
</template>
<style scoped>
.cadence-resource-navigation {
  display: flex;
  align-items: center;
  gap: 16px;
  border-bottom: 1px solid var(--border-subtle);
  min-width: 0;
}
nav {
  display: flex;
  gap: 4px;
  overflow-x: auto;
  min-width: 0;
}
nav :deep(a) {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 14px 13px;
  border-bottom: 2px solid transparent;
  color: var(--text-muted);
  text-decoration: none;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 550;
}
nav :deep(a:hover) {
  color: var(--text-bright);
  background: var(--state-hover);
}
nav :deep(a[aria-current="page"]) {
  color: var(--color-action);
  border-bottom-color: var(--color-action);
}
nav :deep(a:focus-visible) {
  outline: 2px solid var(--border-focus);
  outline-offset: -3px;
}
.cadence-resource-navigation__status {
  margin-inline-start: auto;
  color: var(--text-subtle);
  white-space: nowrap;
  font: 10px var(--font-mono);
}
@media (width < 700px) {
  .cadence-resource-navigation {
    flex-wrap: wrap;
    gap: 0;
  }
  .cadence-resource-navigation__status {
    padding: 0 8px 8px;
  }
}
</style>
