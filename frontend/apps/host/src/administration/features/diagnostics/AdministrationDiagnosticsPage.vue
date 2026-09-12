<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import type { DiagnosticsSnapshot, DiagnosticsPanelInteractions } from "@cadence/plugin-sdk";
import { administrationDiagnostics } from "./contributions";
import DiagnosticsContributionBoundary from "./DiagnosticsContributionBoundary.vue";

defineProps<{
  snapshots: readonly DiagnosticsSnapshot[];
  interactions: DiagnosticsPanelInteractions;
  refreshing?: boolean;
}>();
const emit = defineEmits<{ refresh: [] }>();
</script>
<template>
  <div id="administration-diagnostics-page" class="space-y-6">
    <CadencePageHeading
      :breadcrumbs="[{ label: 'Platform Admin', href: '/admin' }, { label: 'Runtime Diagnostics' }]"
    >
      <template #title>Runtime Diagnostics</template>
      <template #description>Platform and module diagnostics for support workflows.</template>
      <template #actions>
        <button
          id="admin-runtime-refresh"
          type="button"
          class="btn btn-secondary btn-sm"
          :disabled="refreshing"
          @click="emit('refresh')"
        >
          <span class="hero-arrow-path h-4 w-4" aria-hidden="true"></span> Refresh
        </button>
      </template>
    </CadencePageHeading>
    <DiagnosticsContributionBoundary
      v-for="contribution in administrationDiagnostics"
      :key="contribution.id"
      :contribution="contribution"
      :snapshots="snapshots"
      :interactions="interactions"
    />
  </div>
</template>
