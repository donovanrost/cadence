<script setup lang="ts">
import { ApListRow, ApPanel } from "@/ui";
import { checkState, type ReadinessCheck } from "./detail.ts";

/** D1 Readiness checks for one spacecraft (telemetry is informational). */
defineProps<{ checks: readonly ReadinessCheck[] }>();
</script>

<template>
  <ApPanel index="D1" title="Readiness" flush>
    <ul class="m-0 list-none p-0">
      <ApListRow
        v-for="check in checks"
        :key="check.key"
        :state="checkState(check.status)"
        :title="check.title"
        :sentence="check.body"
      />
    </ul>
  </ApPanel>
</template>
