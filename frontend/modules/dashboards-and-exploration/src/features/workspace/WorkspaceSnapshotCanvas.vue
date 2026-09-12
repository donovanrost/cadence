<script setup lang="ts">
import { computed, provide } from "vue";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import DashboardCanvas from "./DashboardCanvas.vue";
import { CHART_RUNTIME_PORT } from "./chart-runtime";
import { readWorkspaceSnapshot } from "./validation";
import { snapshotPresentation } from "./snapshot-presentation";

const props = defineProps<{ snapshot: unknown; context: OpsPageContext; instanceId: string }>();
const model = computed(() => readWorkspaceSnapshot(props.snapshot, props.context));
const presentation = computed(() => snapshotPresentation(model.value, props.instanceId));
// This read-only renderer does not acquire a legacy ancestor's command bridge.
// Scoped live delivery and evidence actions require a separate admitted port.
provide(CHART_RUNTIME_PORT, { version: 1, execute() {}, subscribe: () => () => {} });
// Data refreshes retain native grid/disclosure identity. Different resources,
// runtime contexts or grid geometry must not inherit another canvas's state.
const canvasKey = computed(() =>
  JSON.stringify([
    props.instanceId,
    model.value.organization_id,
    model.value.mission_id,
    model.value.dashboard_id,
    model.value.document_mode,
    model.value.context,
    model.value.grid,
  ]),
);
</script>

<template>
  <section :id="`${instanceId}-snapshot`" class="min-w-0" aria-label="Dashboard snapshot">
    <div
      v-if="model.warnings.length"
      :id="`${instanceId}-warnings`"
      role="status"
      class="mb-3 border-l-2 border-warning/50 p-3 text-xs"
    >
      <p v-for="warning in model.warnings" :key="`${warning.code}:${warning.severity}`">
        {{ warning.severity }}: {{ warning.code.replaceAll("_", " ") }}
      </p>
    </div>
    <DashboardCanvas :key="canvasKey" :presentation="presentation" />
  </section>
</template>
