<script setup lang="ts">
type Status = "info" | "ready" | "attention" | "blocked";

const props = withDefaults(
  defineProps<{
    status: Status;
    label: string;
  }>(),
  { status: "info" },
);

const statusTones = {
  info: "info",
  ready: "success",
  attention: "warning",
  blocked: "error",
} as const satisfies Record<Status, "info" | "success" | "warning" | "error">;
</script>

<template>
  <span
    :class="[
      'mission-catalog-status-badge',
      `mission-catalog-status-badge--${statusTones[props.status]}`,
    ]"
  >
    {{ props.label }}
  </span>
</template>

<style scoped>
.mission-catalog-status-badge {
  display: inline-flex;
  align-items: center;
  min-height: 1.5rem;
  padding: 0 0.55rem;
  border: 1px solid currentcolor;
  border-radius: 999px;
  font-family: var(--cadence-font-mono);
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.mission-catalog-status-badge--info {
  color: var(--cadence-color-signal);
}

.mission-catalog-status-badge--success {
  color: var(--cadence-color-success);
}

.mission-catalog-status-badge--warning {
  color: var(--cadence-color-warning);
}

.mission-catalog-status-badge--error {
  color: var(--cadence-color-danger);
}
</style>
