<script setup lang="ts">
import { ApTabLinks } from "@/ui";

/** Ops › Telemetry has two views (ux IA §06): Explore and Dashboards. */
defineProps<{ active: "explore" | "dashboards" }>();
const links = [
  { key: "explore", label: "Explore", to: { name: "ops.telemetry" } },
  { key: "dashboards", label: "Dashboards", to: { name: "ops.dashboards" } },
] as const;
</script>

<template>
  <ApTabLinks :links="links" :active="active" label="Telemetry views" />
</template>
