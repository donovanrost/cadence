<script setup lang="ts">
withDefaults(
  defineProps<{
    pulse?: boolean;
    tone?: "nominal" | "warning" | "danger" | "neutral";
  }>(),
  {
    pulse: false,
    tone: "neutral",
  },
);
</script>

<template>
  <span :class="['cui-status', `cui-status--${tone}`]">
    <span
      :class="['cui-status__dot', { 'cui-status__dot--pulse': pulse }]"
      aria-hidden="true"
    ></span>
    <span class="cui-status__label"><slot /></span>
  </span>
</template>

<style scoped>
.cui-status {
  display: inline-flex;
  align-items: center;
  gap: var(--cadence-space-2);
  color: var(--cadence-color-text-secondary);
}

.cui-status__dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  color: var(--cadence-color-text-muted);
  background: var(--cadence-color-text-muted);
}

.cui-status--nominal .cui-status__dot {
  color: var(--cadence-color-signal);
  background: var(--cadence-color-signal);
}

.cui-status--warning .cui-status__dot {
  color: var(--cadence-color-accent);
  background: var(--cadence-color-accent);
}

.cui-status--danger .cui-status__dot {
  color: var(--cadence-color-danger);
  background: var(--cadence-color-danger);
}

.cui-status__dot--pulse {
  box-shadow: 0 0 8px color-mix(in srgb, currentcolor 55%, transparent);
}
</style>
