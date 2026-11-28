<script setup lang="ts">
import { ApCallout, ApPanel } from "@/ui";
import { MONITORING_EDITS_PENDING } from "@/features/telemetry/index.ts";

/** Profile.md P1 Limits: read-only notice; limits apply per point, mission-wide (#669, #451). */
</script>

<template>
  <ApPanel index="P1" title="Limits">
    <ApCallout tone="info"
      >Limits apply mission-wide per point; per-profile limits aren't supported yet.
      {{ MONITORING_EDITS_PENDING }}</ApCallout
    >
  </ApPanel>
</template>
