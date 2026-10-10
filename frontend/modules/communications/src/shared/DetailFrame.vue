<script setup lang="ts">
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
/** A record's saved configuration; the routed page describes its header. */
defineProps<{ id: string; facts: Array<{ label: string; value: string | number }> }>();
</script>
<template>
  <section :id="id" class="space-y-6">
    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
      <p class="hud-label mb-4">Saved configuration</p>
      <CadenceDataRow
        v-for="fact in facts"
        :key="fact.label"
        row-class="hud-data-row"
        label-class="hud-data-label"
        :label="fact.label"
        ><span class="hud-data-value">{{ fact.value }}</span></CadenceDataRow
      >
      <p class="mt-6 text-sm text-base-content/65">
        This describes saved setup, not runtime connectivity or operational readiness.
      </p>
    </CadenceCard>
  </section>
</template>
