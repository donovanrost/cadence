<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import StatusBadge from "./StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";

type Status = {
  tone: "info";
  label: string;
};

type Breadcrumb = {
  label: string;
  href: string | null;
};

type CommandingPage = {
  id: string;
  title: string;
  subtitle: string;
  eyebrow: string;
  breadcrumbs: Breadcrumb[];
  status: Status;
};

type CommandPanel = {
  id: string;
  title: string;
  value: string;
  status: Status;
  description: string;
};

type ReadinessImpact = {
  eyebrow: string;
  title: string;
  description: string;
  status: Status;
};

defineProps<{
  page: CommandingPage;
  panels: CommandPanel[];
  readiness: ReadinessImpact;
}>();
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.title }}</template>
      <template #eyebrow>{{ page.eyebrow }}</template>
      <template #description>{{ page.subtitle }}</template>
      <template #actions
        ><StatusBadge :status="page.status.tone" :label="page.status.label"
      /></template>
    </CadencePageHeading>

    <section class="grid gap-4 lg:grid-cols-3">
      <CadenceCard
        v-for="panel in panels"
        :id="panel.id"
        :key="panel.id"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="hud-label mb-2">{{ panel.title }}</p>
            <h2 class="text-base font-semibold">{{ panel.value }}</h2>
          </div>
          <StatusBadge :status="panel.status.tone" :label="panel.status.label" />
        </div>
        <p class="mt-3 text-sm text-base-content/70">{{ panel.description }}</p>
      </CadenceCard>
    </section>

    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">{{ readiness.eyebrow }}</p>
          <h2 class="text-lg font-semibold">{{ readiness.title }}</h2>
          <p class="mt-1 max-w-2xl text-sm text-base-content/70">
            {{ readiness.description }}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <StatusBadge :status="readiness.status.tone" :label="readiness.status.label" />
        </div>
      </div>
    </CadenceCard>
  </div>
</template>
