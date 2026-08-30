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
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--cadence-space-5);
  overflow: hidden;
  min-height: 320px;
  padding: var(--cadence-space-8);
  color: var(--cadence-color-text-secondary);
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface);
}

.cui-state-panel::before {
  position: absolute;
  top: 18px;
  left: 18px;
  width: 8px;
  height: 8px;
  border-top: 1px solid var(--cadence-color-border-strong);
  border-left: 1px solid var(--cadence-color-border-strong);
  content: "";
}

.cui-state-panel strong {
  display: block;
  margin-bottom: var(--cadence-space-1);
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-display);
  font-size: var(--cadence-type-title-md);
  font-weight: 520;
  letter-spacing: -0.025em;
  line-height: 1.1;
}

.cui-state-panel p {
  margin: 0;
  font-size: var(--cadence-type-body-md);
  line-height: var(--cadence-leading-copy);
}

.cui-state-panel__mark {
  display: grid;
  width: 42px;
  height: 42px;
  border: 1px solid var(--cadence-color-border-strong);
  color: var(--cadence-color-text-secondary);
  background: transparent;
  font-family: var(--cadence-font-mono);
  font-size: 0.75rem;
  place-items: center;
}

.cui-state-panel--error .cui-state-panel__mark {
  border-color: var(--cadence-color-danger);
  color: var(--cadence-color-danger);
}

.cui-state-panel__action {
  margin-top: var(--cadence-space-5);
}
</style>
