<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import StatusBadge from "./StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";

type StatusTone = "ready" | "attention" | "blocked" | "info";

type Status = {
  tone: StatusTone;
  label: string;
};

type Breadcrumb = {
  label: string;
  href: string | null;
};

type ReadinessPage = {
  id: string;
  title: string;
  title_suffix: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
  status: Status;
};

type Detail = {
  label: string;
  value: string;
};

type Action = {
  label: string;
  href: string;
};

type ApplicationList = {
  id: string;
  empty_state: {
    id: string;
    description: string;
  };
};

type ReadinessPanel = {
  id: string;
  title: string;
  status: Status;
  description: string;
  details: Detail[];
  action: Action;
  application_list: ApplicationList | null;
};

type ReadinessApplication = {
  id: string;
  application_key: string;
  display_name: string;
  status: Status;
};

defineProps<{
  page: ReadinessPage;
  panels: ReadinessPanel[];
  applications: ReadinessApplication[];
}>();
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.title }} </template>
      <template #description>{{ page.subtitle }}</template>
      <template #metadata
        ><span>
          {{ page.title_suffix }}
        </span></template
      >
      <template #actions
        ><StatusBadge :status="page.status.tone" :label="page.status.label"
      /></template>
    </CadencePageHeading>

    <div class="grid gap-4 xl:grid-cols-2">
      <CadenceCard
        v-for="panel in panels"
        :id="panel.id"
        :key="panel.id"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="hud-label">{{ panel.title }}</p>
          <StatusBadge :status="panel.status.tone" :label="panel.status.label" />
        </div>
        <h2 class="mt-3 text-base font-semibold">{{ panel.status.label }}</h2>
        <p class="mt-1 text-sm text-base-content/70">{{ panel.description }}</p>

        <div class="mt-5 space-y-1">
          <CadenceDataRow
            v-for="detail in panel.details"
            :key="detail.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="detail.label"
          >
            <span class="hud-data-value">{{ detail.value }}</span>
          </CadenceDataRow>

          <div v-if="panel.application_list !== null" :id="panel.application_list.id">
            <p
              :id="panel.application_list.empty_state.id"
              class="hidden only:block text-sm text-base-content/60"
            >
              {{ panel.application_list.empty_state.description }}
            </p>
            <div
              v-for="application in applications"
              :id="application.id"
              :key="application.application_key"
            >
              <CadenceDataRow
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="application.display_name"
              >
                <span class="hud-data-value">{{ application.status.label }}</span>
              </CadenceDataRow>
            </div>
          </div>
        </div>

        <a
          :href="panel.action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm mt-5"
          >{{ panel.action.label }}</a
        >
      </CadenceCard>
    </div>
  </div>
</template>
