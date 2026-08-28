<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"
import CadencePanel from "./ui/components/CadencePanel.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"
import StatusBadge from "./StatusBadge.vue"

type StatusTone = "info" | "ready" | "attention" | "blocked"

type Breadcrumb = {
  label: string
  href: string | null
}

type Navigation = {
  breadcrumbs: Breadcrumb[]
}

type SummaryTile = {
  id: string
  label: string
  value: string | number
}

type Provider = {
  page_id: string
  display_name: string
  provider_id: string
  simulated_badge: {
    id: string
    label: string
  }
  version: string
  summary_tiles: SummaryTile[]
}

type Action = {
  id: string
  label: string
  disabled: boolean
}

type Actions = {
  validate: Action
  sync: Action
  archive: Action & {confirm: string}
}

type ProfileSection = {
  id: string
  heading: string
  subtitle: string
  empty: boolean
  empty_copy: string
  table_id: string
  table_body_id: string
  columns: string[]
}

type Profiles = {
  service: ProfileSection
  delivery: ProfileSection
}

type Status = {
  tone: StatusTone
  label: string
}

type ServiceProfile = {
  __dom_id: string
  id: string
  display_name: string
  service_kind: string
  direction: string
  data_families: string
  status: Status
}

type DeliveryProfile = {
  __dom_id: string
  id: string
  display_name: string
  operator_summary: string
  delivery_kind: string
  direction: string
  status: Status
}

type Detail = {
  label: string
  value: string
  mono: boolean
}

type DetailCard = {
  id: string
  title: string
  rows: Detail[]
}

type Capabilities = {
  id: string
  title: string
  empty: boolean
  empty_copy: string
  items: Array<{
    label: string
    status: Status
  }>
}

type Details = {
  configuration: DetailCard
  delivery_policy: DetailCard
  capabilities: Capabilities
  version_history: {
    id: string
    title: string
    stream_id: string
  }
}

type Diagnostics = {
  id: string
  label: string
  json_id: string
  rows: Detail[]
  json: string
}

type ProviderVersion = {
  __dom_id: string
  version: number
  lifecycle_state: string
}

const props = defineProps<{
  navigation: Navigation
  provider: Provider
  actions: Actions
  profiles: Profiles
  details: Details
  diagnostics: Diagnostics
  service_profiles: ServiceProfile[]
  delivery_profiles: DeliveryProfile[]
  provider_versions: ProviderVersion[]
}>()

const emit = defineEmits<{
  "validate-provider": []
  "sync-provider": []
  "archive-provider": []
}>()

const archiveProvider = () => {
  if (window.confirm(props.actions.archive.confirm)) emit("archive-provider")
}
</script>

<template>
  <div :id="provider.page_id" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div class="flex items-end justify-between gap-4">
        <div>
          <nav
            aria-label="Breadcrumb"
            class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          >
            <template
              v-for="(breadcrumb, index) in navigation.breadcrumbs"
              :key="`${index}-${breadcrumb.label}`"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span v-if="breadcrumb.href === null" class="text-primary/90">
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </nav>

          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ provider.display_name }}
            <span class="ml-3 font-mono text-base text-base-content/60">
              <span
                :id="provider.simulated_badge.id"
                class="inline-flex rounded-full bg-info/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-info"
              >{{ provider.simulated_badge.label }}</span>
              <span class="ml-2 font-mono text-xs text-base-content/60">
                {{ provider.version }}
              </span>
            </span>
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ provider.provider_id }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <button
            :id="actions.validate.id"
            type="button"
            class="btn btn-secondary btn-sm"
            :disabled="actions.validate.disabled"
            @click="emit('validate-provider')"
          >
            <span class="hero-shield-check h-4 w-4"></span>
            {{ actions.validate.label }}
          </button>
          <button
            :id="actions.sync.id"
            type="button"
            class="btn btn-primary btn-sm"
            :disabled="actions.sync.disabled"
            @click="emit('sync-provider')"
          >
            <span class="hero-arrow-path h-4 w-4"></span>
            {{ actions.sync.label }}
          </button>
          <button
            :id="actions.archive.id"
            type="button"
            class="btn btn-error btn-outline btn-sm"
            :data-confirm="actions.archive.confirm"
            :disabled="actions.archive.disabled"
            @click="archiveProvider"
          >
            {{ actions.archive.label }}
          </button>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="grid gap-3 md:grid-cols-4">
      <div
        v-for="summary in provider.summary_tiles"
        :id="summary.id"
        :key="summary.id"
        class="border border-base-300 bg-base-200 px-3 py-2"
      >
        <p class="hud-label">{{ summary.label }}</p>
        <p class="mt-1 font-mono text-xl text-base-content">{{ summary.value }}</p>
      </div>
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

        <CadenceCard :id="details.capabilities.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
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
                <StatusBadge
                  :status="capability.status.tone"
                  :label="capability.status.label"
                />
              </div>
            </div>
        </CadenceCard>

        <CadenceCard :id="details.version_history.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
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

    <details
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
    </details>
  </div>
</template>
