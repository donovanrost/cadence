<script setup lang="ts">
import CadenceBadge from "./ui/components/CadenceBadge.vue";

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
  <CadenceBadge :tone="statusTones[props.status]">{{ props.label }}</CadenceBadge>
</template>
