<script setup lang="ts">
import CSpinner from "./CSpinner.vue";

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
    <CSpinner v-if="tone === 'loading'" :label="title" />
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
  justify-content: center;
  gap: var(--cadence-space-4);
  min-height: 320px;
  padding: var(--cadence-space-8);
  color: var(--cadence-color-text-secondary);
}

.cui-state-panel strong {
  display: block;
  margin-bottom: 5px;
  color: var(--cadence-color-text);
  font-weight: 600;
}

.cui-state-panel p {
  margin: 0;
  font-size: 13px;
}

.cui-state-panel__mark {
  display: grid;
  width: 34px;
  height: 34px;
  border: 1px solid var(--cadence-color-border-strong);
  color: var(--cadence-color-text-secondary);
  place-items: center;
}

.cui-state-panel--error .cui-state-panel__mark {
  border-color: var(--cadence-color-danger);
  color: var(--cadence-color-danger);
}

.cui-state-panel__action {
  margin-top: var(--cadence-space-4);
}
</style>
