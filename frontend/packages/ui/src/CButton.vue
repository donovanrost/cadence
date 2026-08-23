<script setup lang="ts">
import CSpinner from "./CSpinner.vue";

withDefaults(
  defineProps<{
    disabled?: boolean;
    loading?: boolean;
    size?: "sm" | "md";
    type?: "button" | "submit" | "reset";
    variant?: "primary" | "secondary" | "quiet" | "danger";
  }>(),
  {
    disabled: false,
    loading: false,
    size: "md",
    type: "button",
    variant: "secondary",
  },
);
</script>

<template>
  <button
    :class="['cui-button', `cui-button--${variant}`, `cui-button--${size}`]"
    :type="type"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
  >
    <CSpinner v-if="loading" size="sm" />
    <span class="cui-button__label"><slot /></span>
  </button>
</template>

<style scoped>
.cui-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--cadence-space-2);
  border: 1px solid var(--cadence-color-border-strong);
  border-radius: 0;
  color: var(--cadence-color-text);
  background: var(--cadence-color-surface-raised);
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  font-weight: 650;
  letter-spacing: 0.055em;
  line-height: 1;
  text-transform: uppercase;
  cursor: pointer;
  transition:
    color var(--cadence-transition-fast),
    border-color var(--cadence-transition-fast),
    background var(--cadence-transition-fast);
}

.cui-button--sm {
  min-height: var(--cadence-control-sm);
  padding: 0 var(--cadence-space-3);
}

.cui-button--md {
  min-height: var(--cadence-control-md);
  padding: 0 var(--cadence-space-4);
}

.cui-button:hover:not(:disabled) {
  border-color: var(--cadence-color-text-muted);
  color: var(--cadence-color-text-strong);
  background: #20292b;
}

.cui-button--primary {
  border-color: var(--cadence-color-accent);
  color: #17130d;
  background: var(--cadence-color-accent);
}

.cui-button--primary:hover:not(:disabled) {
  border-color: #ffb748;
  color: #17130d;
  background: #ffb748;
}

.cui-button--primary :deep(.cui-spinner) {
  border-color: rgb(23 19 13 / 35%);
  border-top-color: #17130d;
}

.cui-button--quiet {
  border-color: transparent;
  background: transparent;
}

.cui-button--danger {
  border-color: color-mix(in srgb, var(--cadence-color-danger) 55%, transparent);
  color: var(--cadence-color-danger);
  background: color-mix(in srgb, var(--cadence-color-danger) 8%, transparent);
}

.cui-button:disabled {
  border-color: var(--cadence-color-border);
  color: var(--cadence-color-text-muted);
  background: var(--cadence-color-surface);
  cursor: not-allowed;
}
</style>
