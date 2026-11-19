<script setup lang="ts">
import { ApCallout } from "@/ui";

/**
 * api-ops 17deb3c1: when the telemetry store doesn't answer in time, the fleet read answers from
 * live values and limits and says `telemetry: degraded`. Freshness may then be incomplete.
 */
defineProps<{ telemetry: "ok" | "degraded" | undefined }>();
</script>

<template>
  <ApCallout v-if="telemetry === 'degraded'" tone="stale">
    Telemetry history unavailable: freshness may be incomplete.
  </ApCallout>
</template>
