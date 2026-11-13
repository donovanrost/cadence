<script setup lang="ts">
import { computed, onMounted } from "vue";
import { useMissionScope } from "@/shell/index.ts";
import { ApEmptyState, ApPanel } from "@/ui";

/**
 * The dashboard directory is still the legacy page until D1–D4 land (plans/dashboards.md slice
 * 2); the viewer is the console's own (ops.dashboard).
 */
const scope = useMissionScope();
const href = computed(
  () => `/missions/${encodeURIComponent(scope.value.mission.id)}/ops/dashboards`,
);
onMounted(() => window.location.assign(href.value));
</script>

<template>
  <ApPanel index="D" title="Dashboards" flush>
    <ApEmptyState state="off" headline="Opening dashboards…">
      <a :href="href" class="text-readout underline">Open the dashboard pages</a>
    </ApEmptyState>
  </ApPanel>
</template>
