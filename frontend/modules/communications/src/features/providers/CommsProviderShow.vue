<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import CadenceStatTile from "@cadence/ui/CadenceStatTile.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import StatusBadge from "../../shared/StatusBadge.vue";

import type { ProviderDetailModel } from "./provider-detail.contracts";

const props = defineProps<ProviderDetailModel>();

const emit = defineEmits<{
  "validate-provider": [];
  "sync-provider": [];
  "archive-provider": [];
}>();

const archiveProvider = () => {
  if (window.confirm(props.actions.archive.confirm)) emit("archive-provider");
};
</script>

<template>
  <div :id="provider.page_id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ provider.display_name }} </template>
      <template #description>{{ provider.provider_id }}</template>
      <template #metadata
        ><span>
          <span
            :id="provider.simulated_badge.id"
            class="inline-flex rounded-full bg-info/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-info"
            >{{ provider.simulated_badge.label }}</span
          >
          <span class="ml-2 font-mono text-xs text-base-content/60">
            {{ provider.version }}
          </span>
        </span></template
      >
      <template #actions
        ><button
          :id="actions.validate.id"
          type="button"
          class="btn btn-secondary btn-sm"
          :disabled="actions.validate.disabled"
          @click="emit('validate-provider')"
        >
          <span class="hero-shield-check h-4 w-4"></span>
          {{ actions.validate.label }}</button
        ><button
          :id="actions.sync.id"
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="actions.sync.disabled"
          @click="emit('sync-provider')"
        >
          <span class="hero-arrow-path h-4 w-4"></span>
          {{ actions.sync.label }}</button
        ><button
          :id="actions.archive.id"
          type="button"
          class="btn btn-error btn-outline btn-sm"
          :data-confirm="actions.archive.confirm"
          :disabled="actions.archive.disabled"
          @click="archiveProvider"
        >
          {{ actions.archive.label }}
        </button></template
      >
    </CadencePageHeading>

    <div class="grid gap-3 md:grid-cols-4">
      <CadenceStatTile v-for="summary in provider.summary_tiles" :id="summary.id" :key="summary.id">
        <template #label>{{ summary.label }}</template>
        <p class="mt-1 font-mono text-xl text-base-content">{{ summary.value }}</p>
      </CadenceStatTile>
    </div>

    <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_22rem]">
      <div class="space-y-4">
        <CadencePanel
          :id="profiles.service.id"
          class="card bg-base-200 border border-base-300"
          header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <h2 class="text-base font-semibold text-base-content">
                {{ profiles.service.heading }}
              </h2>
              <p class="mt-1 text-xs text-base-content/70">
                {{ profiles.service.subtitle }}
              </p>
            </div>
          </template>
          <div class="card-body p-0">
            <div v-if="profiles.service.empty" class="p-6 text-sm text-base-content/60">
              {{ profiles.service.empty_copy }}
            </div>
            <CadenceTableFrame v-else :id="profiles.service.table_id">
              <thead>
                <tr>
                  <th v-for="column in profiles.service.columns" :key="column" class="hud-label">
                    {{ column }}
                  </th>
                </tr>
              </thead>
              <tbody :id="profiles.service.table_body_id" phx-update="stream">
                <tr
                  v-for="profile in service_profiles"
                  :id="profile.__dom_id"
                  :key="profile.__dom_id"
                  class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
                >
                  <td>{{ profile.display_name }}</td>
                  <td class="font-mono text-sm">{{ profile.service_kind }}</td>
                  <td class="font-mono text-sm">{{ profile.direction }}</td>
                  <td class="font-mono text-sm">{{ profile.data_families }}</td>
                  <td>
                    <StatusBadge :status="profile.status.tone" :label="profile.status.label" />
                  </td>
                </tr>
              </tbody>
            </CadenceTableFrame>
          </div>
        </CadencePanel>

        <CadencePanel
          :id="profiles.delivery.id"
          class="card bg-base-200 border border-base-300"
          header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <h2 class="text-base font-semibold text-base-content">
                {{ profiles.delivery.heading }}
              </h2>
              <p class="mt-1 text-xs text-base-content/70">
                {{ profiles.delivery.subtitle }}
              </p>
            </div>
          </template>
          <div class="card-body p-0">
            <div v-if="profiles.delivery.empty" class="p-6 text-sm text-base-content/60">
              {{ profiles.delivery.empty_copy }}
            </div>
            <CadenceTableFrame v-else :id="profiles.delivery.table_id">
              <thead>
                <tr>
                  <th v-for="column in profiles.delivery.columns" :key="column" class="hud-label">
                    {{ column }}
                  </th>
                </tr>
              </thead>
              <tbody :id="profiles.delivery.table_body_id" phx-update="stream">
                <tr
                  v-for="profile in delivery_profiles"
                  :id="profile.__dom_id"
                  :key="profile.__dom_id"
                  class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
                >
                  <td>
                    <div>{{ profile.display_name }}</div>
                    <div class="mt-1 text-xs text-base-content/60">
                      {{ profile.operator_summary }}
                    </div>
                  </td>
                  <td class="font-mono text-sm">{{ profile.delivery_kind }}</td>
                  <td class="font-mono text-sm">{{ profile.direction }}</td>
                  <td>
                    <StatusBadge :status="profile.status.tone" :label="profile.status.label" />
                  </td>
                </tr>
              </tbody>
            </CadenceTableFrame>
          </div>
        </CadencePanel>
      </div>

      <aside class="space-y-4">
        <CadenceCard
          v-for="card in [details.configuration, details.delivery_policy]"
          :id="card.id"
          :key="card.id"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-6"
        >
          <p class="hud-label">{{ card.title }}</p>
          <div class="mt-3 divide-y divide-base-300">
            <CadenceDataRow
              v-for="row in card.rows"
              :key="row.label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="row.label"
            >
              <span :class="['hud-data-value', row.mono && 'font-mono text-sm']">
                {{ row.value }}
              </span>
            </CadenceDataRow>
          </div>
        </CadenceCard>

        <CadenceCard
          :id="details.capabilities.id"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-6"
        >
          <p class="hud-label">{{ details.capabilities.title }}</p>
          <div class="mt-3 space-y-2">
            <div v-if="details.capabilities.empty" class="text-sm text-base-content/60">
              {{ details.capabilities.empty_copy }}
            </div>
            <div
              v-for="capability in details.capabilities.items"
              :key="capability.label"
              class="flex items-center justify-between gap-3 text-sm"
            >
              <span>{{ capability.label }}</span>
              <StatusBadge :status="capability.status.tone" :label="capability.status.label" />
            </div>
          </div>
        </CadenceCard>

        <CadenceCard
          :id="details.version_history.id"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-6"
        >
          <p class="hud-label">{{ details.version_history.title }}</p>
          <div
            :id="details.version_history.stream_id"
            phx-update="stream"
            class="mt-3 divide-y divide-base-300"
          >
            <div
              v-for="version in provider_versions"
              :id="version.__dom_id"
              :key="version.__dom_id"
            >
              <CadenceDataRow
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="`v${version.version}`"
              >
                <span class="hud-data-value">{{ version.lifecycle_state }}</span>
              </CadenceDataRow>
            </div>
          </div>
        </CadenceCard>
      </aside>
    </div>

    <CadenceDetailsFrame
      :id="diagnostics.id"
      class="rounded border border-base-300 bg-base-200/60 p-4 text-sm"
    >
      <summary class="cursor-pointer hud-label hover:text-primary">
        {{ diagnostics.label }}
      </summary>
      <div class="mt-4 grid gap-4 lg:grid-cols-2">
        <div class="divide-y divide-base-300">
          <CadenceDataRow
            v-for="row in diagnostics.rows"
            :key="row.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="row.label"
          >
            <span :class="['hud-data-value', row.mono && 'font-mono text-sm']">
              {{ row.value }}
            </span>
          </CadenceDataRow>
        </div>
        <pre
          :id="diagnostics.json_id"
          class="max-h-80 overflow-auto border border-base-300 bg-base-100/50 p-3 font-mono text-xs text-base-content/70"
          >{{ diagnostics.json }}</pre>
      </div>
    </CadenceDetailsFrame>
  </div>
</template>
