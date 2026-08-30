<script setup lang="ts">
withDefaults(
  defineProps<{
    label?: string;
    size?: "sm" | "md";
  }>(),
  {
    label: undefined,
    size: "md",
  },
);
</script>

<template>
  <span
    :class="['cui-spinner', `cui-spinner--${size}`]"
    :role="label ? 'status' : undefined"
    :aria-label="label"
    :aria-hidden="label ? undefined : true"
  ></span>
</template>

<style scoped>
.cui-spinner {
  position: relative;
  display: inline-block;
  flex: none;
  border: 1px solid var(--cadence-color-border-subtle);
  border-top-color: currentcolor;
  border-right-color: currentcolor;
  color: var(--cadence-color-signal);
  animation: cui-spin 640ms steps(8) infinite;
}

.cui-spinner--sm {
  width: 12px;
  height: 12px;
}

.cui-spinner--md {
  width: 22px;
  height: 22px;
}

@keyframes cui-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
