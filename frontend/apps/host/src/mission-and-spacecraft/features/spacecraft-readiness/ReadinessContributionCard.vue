<script setup lang="ts">
import type { ReadinessContribution } from "@cadence/plugin-sdk";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import StatusBadge from "../../shared/StatusBadge.vue";
defineProps<{ contribution: ReadinessContribution | null; index: number }>();
</script>
<template>
  <CadenceCard
    :id="'readiness-contribution-' + index"
    class="card bg-base-200 border border-base-300"
    body-class="card-body p-6"
  >
    <template v-if="contribution">
      <div class="flex items-start justify-between gap-4">
        <h2 class="hud-label">{{ contribution.title }}</h2>
        <StatusBadge :status="contribution.status.tone" :label="contribution.status.label" />
      </div>
      <p
        v-if="contribution.availability === 'unavailable'"
        role="alert"
        class="mt-3 text-sm text-warning"
      >
        This readiness contribution could not be loaded.
      </p>
      <div class="mt-5 space-y-1">
        <CadenceDataRow
          v-for="(detail, index) in contribution.details"
          :key="index"
          row-class="hud-data-row"
          label-class="hud-data-label"
          :label="detail.label"
        >
          <span class="hud-data-value">{{ detail.value }}</span>
        </CadenceDataRow>
      </div>
      <a
        v-if="contribution.action"
        :href="contribution.action.href"
        class="btn btn-primary btn-sm mt-5"
        >{{ contribution.action.label }}</a
      >
    </template>
    <p v-else role="alert" class="text-sm text-warning">
      A readiness contribution is unavailable. Other setup information remains available.
    </p>
  </CadenceCard>
</template>
