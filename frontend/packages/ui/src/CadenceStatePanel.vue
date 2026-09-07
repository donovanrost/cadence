<script setup lang="ts">
import CadenceSpinner from "./CadenceSpinner.vue";

withDefaults(
  defineProps<{
    description?: string;
    title: string;
    tone?: "loading" | "error" | "neutral";
  }>(),
  {
    description: undefined,
    tone: "neutral",
  },
);
</script>

<template>
  <section :class="['cui-state-panel', `cui-state-panel--${tone}`]">
    <CadenceSpinner v-if="tone === 'loading'" :label="title" />
    <span v-else class="cui-state-panel__mark" aria-hidden="true">
      {{ tone === "error" ? "!" : "·" }}
    </span>
    <div>
      <strong>{{ title }}</strong>
      <p v-if="description">{{ description }}</p>
      <slot />
      <div v-if="$slots.action" class="cui-state-panel__action"><slot name="action" /></div>
    </div>
  </section>
</template>

<style scoped>
.cui-state-panel {
  display: flex;
  align-items: center;
  gap: var(--space-4);
  padding: var(--space-6);
  border: 1px solid var(--border-subtle);
  border-radius: var(--control-radius);
  background: var(--card-surface);
  color: var(--text-subtle);
}
.cui-state-panel strong {
  display: block;
  color: var(--text-bright);
  font-size: var(--type-body-lg);
}
.cui-state-panel p {
  margin-block: var(--space-2);
  font-size: var(--type-body-md);
}
.cui-state-panel__mark {
  font-size: var(--type-title-lg);
}
.cui-state-panel--error {
  border-color: var(--status-critical);
}
.cui-state-panel--error .cui-state-panel__mark {
  color: var(--status-critical);
}
.cui-state-panel__action {
  margin-top: var(--space-4);
}
</style>
