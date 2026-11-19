<script setup lang="ts">
import { ApPanel } from "@/ui";
import { ApCheckRows as CheckRows } from "@/ui";
import { checkRows, type ReadinessCheck } from "./detail.ts";

/** D1 Readiness checks for one spacecraft (telemetry is informational). */
defineProps<{ checks: readonly ReadinessCheck[] }>();
</script>

<template>
  <ApPanel index="D1" title="Readiness" flush>
    <CheckRows :rows="checkRows(checks)" />
  </ApPanel>
</template>
