<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadenceStatTile from "@cadence/ui/CadenceStatTile.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Navigation = {
  breadcrumbs: Breadcrumb[];
};

type SummaryTile = {
  id: string;
  label: string;
  value: string;
};

type Detail = {
  label: string;
  value: string;
  mono: boolean;
  href: string | null;
};

type Diagnostics = {
  id: string;
  json_id: string;
  label: string;
  json: string;
};

type Transport = {
  display_name: string;
  transport_id: string;
  origin_badge: {
    id: string;
    label: string;
  };
  version: string;
  summary_tiles: SummaryTile[];
  capability: {
    eyebrow: string;
    endpoint: string;
    description: string;
    kind: string;
    details: Detail[];
    diagnostics: Diagnostics;
  };
};

type VersionHistory = {
  id: string;
  title: string;
  rows: Array<{
    id: string;
    label: string;
    lifecycle_state: string;
  }>;
};

defineProps<{
  navigation: Navigation;
  transport: Transport;
  version_history: VersionHistory;
}>();
</script>

<template>
  <div id="comms-transport-show-surface" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ transport.display_name }} </template>
      <template #description>{{ transport.transport_id }}</template>
      <template #metadata
        ><span>
          <span
            :id="transport.origin_badge.id"
            class="font-mono text-xs uppercase text-primary/80"
            >{{ transport.origin_badge.label }}</span
          >
          <span class="ml-2 font-mono text-xs text-base-content/60">
            {{ transport.version }}
          </span>
        </span></template
      >
    </CadencePageHeading>

    <div class="grid gap-3 md:grid-cols-4">
      <CadenceStatTile
        v-for="summary in transport.summary_tiles"
        :id="summary.id"
        :key="summary.id"
      >
        <template #label>{{ summary.label }}</template>
        <p class="mt-1 font-mono text-xl text-base-content">{{ summary.value }}</p>
      </CadenceStatTile>
    </div>

    <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label mb-2">{{ transport.capability.eyebrow }}</p>
            <h2 class="text-lg font-semibold font-mono text-primary">
              {{ transport.capability.endpoint }}
            </h2>
            <p class="mt-1 max-w-2xl text-sm text-base-content/70">
              {{ transport.capability.description }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2">
            <span
              class="bg-base-300 px-2 py-1 font-mono text-[0.65rem] uppercase tracking-wide text-base-content/70"
              >{{ transport.capability.kind }}</span
            >
          </div>
        </div>

        <div class="mt-6 space-y-1">
          <CadenceDataRow
            v-for="detail in transport.capability.details"
            :key="detail.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="detail.label"
          >
            <span :class="['hud-data-value', detail.mono && 'font-mono text-sm']">
              <a
                v-if="detail.href"
                :href="detail.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline"
                >{{ detail.value }}</a
              >
              <template v-else>{{ detail.value }}</template>
            </span>
          </CadenceDataRow>
        </div>

        <CadenceDetailsFrame
          :id="transport.capability.diagnostics.id"
          class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm"
        >
          <summary class="cursor-pointer hud-label hover:text-primary">
            {{ transport.capability.diagnostics.label }}
          </summary>
          <pre
            :id="transport.capability.diagnostics.json_id"
            class="mt-3 max-h-96 overflow-auto font-mono text-xs text-base-content/70"
            >{{ transport.capability.diagnostics.json }}</pre>
        </CadenceDetailsFrame>
      </CadenceCard>

      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <p class="hud-label">{{ version_history.title }}</p>
        <div :id="version_history.id" phx-update="stream" class="space-y-1">
          <div v-for="version in version_history.rows" :id="version.id" :key="version.id">
            <CadenceDataRow
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="version.label"
            >
              <span class="hud-data-value">
                <span class="text-xs">{{ version.lifecycle_state }}</span>
              </span>
            </CadenceDataRow>
          </div>
        </div>
      </CadenceCard>
    </div>
  </div>
</template>
