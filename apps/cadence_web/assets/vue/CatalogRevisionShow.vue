<script setup lang="ts">
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Navigation = {
  breadcrumbs: Breadcrumb[]
}

type Revision = {
  title: string
  number_label: string
}

type DetailRow = {
  label: string
  value: string | number | null
  href: string | null
  style: "default" | "mono" | "hash"
}

type DetailCard = {
  id: string
  title: string
  rows: DetailRow[]
}

type RuntimeUsage = {
  id: string
  title: string
  summary_id: string
  summary: string
  action: {
    id: string
    label: string
    disabled: boolean
  }
}

type MissionModel = DetailCard & {
  available: boolean
  empty_message: string
}

defineProps<{
  revision: Revision
  navigation: Navigation
  provenance: DetailCard
  runtime_usage: RuntimeUsage
  mission_model: MissionModel
}>()

const valueClasses: Record<DetailRow["style"], string> = {
  default: "",
  mono: "font-mono",
  hash: "font-mono text-xs break-all"
}
</script>

<template>
  <div id="catalog-revision-show-surface" class="space-y-6">
    <header class="border-b border-primary/20 pb-4">
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
              class="transition-colors hover:text-primary"
            >{{ breadcrumb.label }}</a>
          </template>
        </nav>

        <h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">
          {{ revision.title }}
          <span class="ml-3 font-mono text-base text-base-content/60">
            {{ revision.number_label }}
          </span>
        </h1>
      </div>
    </header>

    <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <CadenceCard
        :id="provenance.id"
        class="card border border-base-300 bg-base-200 lg:col-span-2"
        body-class="card-body p-6"
      >
          <p class="hud-label">{{ provenance.title }}</p>
          <div class="mt-3 divide-y divide-base-300">
            <CadenceDataRow
              v-for="row in provenance.rows"
              :key="row.label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="row.label"
            >
              <span class="hud-data-value" :class="valueClasses[row.style]">
                <a
                  v-if="row.href !== null && row.value !== null"
                  :href="row.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="hover:underline"
                >{{ row.value }}</a>
                <span v-else>{{ row.value ?? "—" }}</span>
              </span>
            </CadenceDataRow>
          </div>
      </CadenceCard>

      <CadenceCard :id="runtime_usage.id" class="card border border-base-300 bg-base-200" body-class="card-body p-6">
          <p class="hud-label">{{ runtime_usage.title }}</p>
          <p :id="runtime_usage.summary_id" class="mt-2 text-sm text-base-content/60">
            {{ runtime_usage.summary }}
          </p>
          <button
            :id="runtime_usage.action.id"
            type="button"
            class="btn btn-ghost btn-sm mt-3"
            :disabled="runtime_usage.action.disabled"
          >
            {{ runtime_usage.action.label }}
          </button>
      </CadenceCard>
    </div>

    <CadenceCard :id="mission_model.id" class="card border border-base-300 bg-base-200" body-class="card-body p-6">
        <p class="hud-label">{{ mission_model.title }}</p>
        <div v-if="mission_model.available" class="mt-3 divide-y divide-base-300">
          <CadenceDataRow
            v-for="row in mission_model.rows"
            :key="row.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="row.label"
          >
            <span class="hud-data-value" :class="valueClasses[row.style]">
              {{ row.value ?? "—" }}
            </span>
          </CadenceDataRow>
        </div>
        <p v-else class="mt-2 text-sm text-base-content/60">
          {{ mission_model.empty_message }}
        </p>
    </CadenceCard>
  </div>
</template>
