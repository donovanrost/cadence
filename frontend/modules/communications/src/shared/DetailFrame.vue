<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import type { Navigation } from "./read-contracts";
defineProps<{
  id: string;
  navigation: Navigation;
  title: string;
  subjectId: string;
  listHref: string;
  facts: Array<{ label: string; value: string | number }>;
}>();
</script>
<template>
  <section :id="id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ title }}</template>
      <template #description>{{ subjectId }}</template>
      <template #actions
        ><a
          :id="id + '-back'"
          :href="listHref"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-sm"
          >Back to list</a
        ><slot name="actions"
      /></template>
    </CadencePageHeading>
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
