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
  <span :class="['cui-status', `cui-status--${tone}`]" :data-active="pulse || undefined">
    <span
      :class="['cui-status__dot', { 'cui-status__dot--pulse': pulse }]"
      aria-hidden="true"
    ></span>
    <span class="cui-status__label"><slot /></span>
  </span>
</template>

<style scoped>
.cui-status {
  --cui-status-color: var(--cadence-color-text-muted);

  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 24px;
  padding: 0 9px 0 7px;
  border: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text);
  background: transparent;
  font-size: var(--cadence-type-body-sm);
  font-weight: 560;
  line-height: 1;
}

.cui-status__dot {
  width: 7px;
  height: 7px;
  color: var(--cui-status-color);
  background: currentcolor;
}

.cui-status--nominal {
  --cui-status-color: var(--cadence-color-success);
}

.cui-status--warning {
  --cui-status-color: var(--cadence-color-warning);
}

.cui-status--danger {
  --cui-status-color: var(--cadence-color-danger);
}

.cui-status[data-active] {
  border-left: 4px solid var(--cui-status-color);
  padding-left: 4px;
}
</style>
