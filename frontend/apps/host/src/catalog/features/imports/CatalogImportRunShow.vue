<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import StatusBadge from "../../shared/StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Navigation = {
  breadcrumbs: Breadcrumb[];
};

type Status = {
  label: string;
  tone: "info" | "ready" | "blocked";
};

type RunDetails = {
  importer: {
    id: string;
    label: string;
  };
  started_at: string;
  completed_at: string | null;
};

type MissionModel = {
  id: string;
  revision_id: string | null;
  declaration_count: number | null;
  plan_count: number;
};

type Diagnostic = {
  code: string;
  message: string;
  detail: string | null;
  path: string | null;
};

type DiagnosticGroup = {
  title: string;
  items: Diagnostic[];
};

defineProps<{
  navigation: Navigation;
  status: Status;
  run_details: RunDetails;
  mission_model: MissionModel | null;
  diagnostic_groups: DiagnosticGroup[];
  failure_reason: string | null;
}>();
</script>

<template>
  <div id="catalog-import-run-show-surface" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title> Import run </template>
      <template #metadata
        ><span> <StatusBadge :status="status.tone" :label="status.label" /> </span
      ></template>
    </CadencePageHeading>

    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
      <div class="text-sm space-y-1">
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Importer</span>
          <span :id="run_details.importer.id" class="font-mono">
            {{ run_details.importer.label }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Started</span>
          <span>{{ run_details.started_at }}</span>
        </div>
        <div v-if="run_details.completed_at" class="flex items-center gap-2">
          <span class="text-base-content/60">Completed</span>
          <span>{{ run_details.completed_at }}</span>
        </div>
      </div>
    </CadenceCard>

    <CadenceCard
      v-if="mission_model"
      :id="mission_model.id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <p class="hud-label">Mission Model</p>
      <div class="divide-y divide-base-300">
        <CadenceDataRow row-class="hud-data-row" label-class="hud-data-label" label="Revision">
          <span class="hud-data-value font-mono text-sm">{{ mission_model.revision_id }}</span>
        </CadenceDataRow>
        <CadenceDataRow row-class="hud-data-row" label-class="hud-data-label" label="Declarations">
          <span class="hud-data-value font-mono text-sm">
            {{ mission_model.declaration_count }}
          </span>
        </CadenceDataRow>
        <CadenceDataRow row-class="hud-data-row" label-class="hud-data-label" label="Plans">
          <span class="hud-data-value font-mono text-sm">{{ mission_model.plan_count }}</span>
        </CadenceDataRow>
      </div>
    </CadenceCard>

    <div v-if="diagnostic_groups.length !== 0" class="space-y-3">
      <CadenceCard
        v-for="group in diagnostic_groups"
        :key="group.title"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <p class="hud-label">{{ group.title }}</p>
        <ul class="space-y-2">
          <li
            v-for="(diagnostic, index) in group.items"
            :key="`${diagnostic.code}-${index}`"
            class="text-sm"
          >
            <span class="font-mono text-xs text-base-content/60">{{ diagnostic.code }}</span>
            <span class="ml-2">{{ diagnostic.message }}</span>
            <p v-if="diagnostic.detail !== null" class="text-xs text-base-content/70 mt-1">
              {{ diagnostic.detail }}
            </p>
            <p v-if="diagnostic.path !== null" class="text-xs text-base-content/60 font-mono mt-1">
              {{ diagnostic.path }}
            </p>
          </li>
        </ul>
      </CadenceCard>
    </div>

    <div
      v-if="failure_reason !== null"
      role="alert"
      class="border px-4 py-3 text-sm text-base-content border-error/40 bg-error/10"
    >
      <p class="font-mono text-sm">{{ failure_reason }}</p>
    </div>
  </div>
</template>
