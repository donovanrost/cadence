<script setup lang="ts">
// Compatibility surface; the host now owns /admin/runtime.
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import {
  DashboardRuntimeDiagnostics,
  type DashboardRuntimeDiagnosticsProps,
  type FilterValues,
} from "@cadence/dashboards-and-exploration";
defineProps<DashboardRuntimeDiagnosticsProps>();
const emit = defineEmits<{
  refresh: [];
  filter_decisions: [payload: { runtime_decision_filters: FilterValues }];
}>();
useManagementHeader("/admin/runtime", {});
</script>
<template>
  <div class="flex justify-end">
    <button
      id="admin-runtime-refresh"
      type="button"
      class="btn btn-secondary btn-sm"
      @click="emit('refresh')"
    >
      Refresh
    </button>
  </div>
  <DashboardRuntimeDiagnostics
    v-bind="$props"
    @filter_decisions="emit('filter_decisions', $event)"
  />
</template>
