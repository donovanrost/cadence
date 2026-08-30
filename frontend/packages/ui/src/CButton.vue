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
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--cadence-space-2);
  overflow: hidden;
  border: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text);
  background: transparent;
  font-size: 0.8125rem;
  font-weight: 620;
  letter-spacing: -0.01em;
  line-height: 1.15;
  cursor: pointer;
  transition:
    color var(--cadence-transition-fast),
    border-color var(--cadence-transition-fast),
    background var(--cadence-transition-fast);
}

.cui-button--sm {
  min-height: var(--cadence-control-sm);
  padding: 0 var(--cadence-space-3);
  font-size: 0.75rem;
}

.cui-button--md {
  min-height: var(--cadence-control-md);
  padding: 0 var(--cadence-space-5);
}

.cui-button:hover:not(:disabled) {
  border-color: var(--cadence-color-border-strong);
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface-inset);
}

.cui-button:active:not(:disabled) {
  color: var(--cadence-color-text-inverse);
  background: var(--cadence-color-surface-inverse);
}

.cui-button--primary {
  border-color: var(--cadence-color-accent);
  color: var(--cadence-color-on-accent);
  background: var(--cadence-color-accent);
}

.cui-button--primary:hover:not(:disabled) {
  border-color: var(--cadence-color-accent-hover);
  color: var(--cadence-color-on-accent);
  background: var(--cadence-color-accent-hover);
}

.cui-button--primary :deep(.cui-spinner) {
  color: var(--cadence-color-on-accent);
}

.cui-button--quiet {
  border-color: transparent;
  background: transparent;
}

.cui-button--quiet:hover:not(:disabled) {
  border-color: transparent;
  color: var(--cadence-color-signal);
  background: transparent;
}

.cui-button--danger {
  border-color: color-mix(in srgb, var(--cadence-color-danger) 45%, var(--cadence-color-border));
  color: var(--cadence-color-danger);
  background: transparent;
}

.cui-button--danger:hover:not(:disabled) {
  border-color: var(--cadence-color-danger);
  color: var(--cadence-color-text-inverse);
  background: var(--cadence-color-danger);
}

.cui-button:disabled {
  border-color: var(--cadence-color-border-subtle);
  color: color-mix(in srgb, var(--cadence-color-text-muted) 58%, transparent);
  background: transparent;
  cursor: not-allowed;
}
</style>
