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
  info: "bg-info/20 text-info",
  ready: "bg-success/20 text-success",
  attention: "bg-warning/20 text-warning",
  blocked: "bg-error/20 text-error",
} as const satisfies Record<Status, string>;
</script>

<template>
  <span
    :class="[
      'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
      statusTones[props.status],
    ]"
  >
    {{ props.label }}
  </span>
</template>
