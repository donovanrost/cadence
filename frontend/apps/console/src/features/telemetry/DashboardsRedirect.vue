<script setup lang="ts">
import { computed, onMounted } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { ApEmptyState, ApPanel } from "@/ui";

/**
 * Dashboards come last (DECISIONS #11): until they're rebuilt here, ops.dashboards hands over to
 * the existing dashboard pages (/missions/:id/ops/dashboards[/:dashboard]), so Telemetry's
 * `Dashboards ↗` and Timeline's dashboard links land on the real thing.
 */
const route = useRoute();
const scope = useMissionScope();
const href = computed(() => {
  const base = `/missions/${encodeURIComponent(scope.value.mission.id)}/ops/dashboards`;
  const id = route.params.dashboardId;
  return typeof id === "string" && id ? `${base}/${encodeURIComponent(id)}` : base;
});
onMounted(() => window.location.assign(href.value));
</script>

<template>
  <ApPanel index="D" title="Dashboards" flush>
    <ApEmptyState state="off" headline="Opening dashboards…">
      <a :href="href" class="text-readout underline">Open the dashboard pages</a>
    </ApEmptyState>
  </ApPanel>
</template>
