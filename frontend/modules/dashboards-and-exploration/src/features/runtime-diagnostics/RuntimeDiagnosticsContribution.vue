<script setup lang="ts">
import type { DiagnosticsPanelInteractions } from "@cadence/plugin-sdk";
import type { DashboardRuntimeDiagnosticsProps, FilterValues } from "./contracts";
import DashboardRuntimeDiagnostics from "./DashboardRuntimeDiagnostics.vue";

const props = defineProps<{
  data: DashboardRuntimeDiagnosticsProps;
  interactions: DiagnosticsPanelInteractions;
}>();
function filter(payload: { runtime_decision_filters: FilterValues }) {
  props.interactions.updateQuery(payload.runtime_decision_filters);
}
</script>
<template>
  <DashboardRuntimeDiagnostics v-bind="data" @filter_decisions="filter" />
</template>
