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
  display: inline-block;
  flex: none;
  border: 2px solid var(--cadence-color-border);
  border-top-color: var(--cadence-color-signal);
  border-radius: 50%;
  animation: cui-spin 700ms linear infinite;
}

.cui-spinner--sm {
  width: 12px;
  height: 12px;
}

.cui-spinner--md {
  width: 20px;
  height: 20px;
}

@keyframes cui-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
