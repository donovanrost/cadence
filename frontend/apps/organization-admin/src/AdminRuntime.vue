<script setup lang="ts">
// Compatibility surface; the host now owns /admin/runtime.
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
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
</script>
<template>
  <CadencePageHeading
    :breadcrumbs="[
      { label: 'Platform Admin', href: navigation.admin_href },
      { label: 'Runtime Diagnostics' },
    ]"
  >
    <template #title>Runtime Diagnostics</template>
    <template #actions
      ><button
        id="admin-runtime-refresh"
        type="button"
        class="btn btn-secondary btn-sm"
        @click="emit('refresh')"
      >
        Refresh
      </button></template
    >
  </CadencePageHeading>
  <DashboardRuntimeDiagnostics
    v-bind="$props"
    @filter_decisions="emit('filter_decisions', $event)"
  />
</template>
