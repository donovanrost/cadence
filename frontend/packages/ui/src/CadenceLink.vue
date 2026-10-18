<script setup lang="ts">
defineProps<{ href: string }>();
</script>

<template>
  <a class="cadence-link" :href="href">
    <slot />
    <span v-if="$slots.icon" class="cadence-link__icon" aria-hidden="true"
      ><slot name="icon"
    /></span>
  </a>
</template>

<style scoped>
.cadence-link {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  color: var(--color-action);
  text-decoration: underline;
  text-decoration-color: color-mix(in srgb, var(--color-action) 40%, transparent);
  text-underline-offset: 0.2em;
  border-radius: var(--radius-xs);
}
.cadence-link:hover {
  color: var(--color-action-muted);
  text-decoration-color: currentColor;
}
.cadence-link:focus-visible {
  outline: 2px solid var(--border-focus);
  outline-offset: 3px;
}
.cadence-link__icon {
  display: inline-flex;
  flex: none;
  width: 1em;
  height: 1em;
}
.cadence-link__icon :deep(*) {
  width: 100%;
  height: 100%;
}
</style>
