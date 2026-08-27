<script setup lang="ts">
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Navigation = {
  breadcrumbs: Breadcrumb[]
}

type Detail = {
  label: string
  value: string
}

type GroundStation = {
  display_name: string
  ground_station_id: string
  lifecycle_state: string
  details_title: string
  description: string
  details: Detail[]
  metadata_title: string
  metadata_json: string
}

type Action = {
  id: string
  label: string
}

type Actions = {
  edit: Action & {href: string}
  archive: Action & {confirm: string}
}

const props = defineProps<{
  navigation: Navigation
  ground_station: GroundStation
  actions: Actions
}>()

const emit = defineEmits<{
  archive: []
}>()

const archive = () => {
  if (window.confirm(props.actions.archive.confirm)) emit("archive")
}
</script>

<template>
  <div class="space-y-6">
    <header class="border-b border-primary/20 pb-4">
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
            {{ ground_station.display_name }}
            <span class="ml-3 font-mono text-base text-base-content/60">
              {{ ground_station.lifecycle_state }}
            </span>
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ ground_station.ground_station_id }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <a
            :id="actions.edit.id"
            :href="actions.edit.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm"
          >{{ actions.edit.label }}</a>
          <button
            :id="actions.archive.id"
            type="button"
            class="btn btn-ghost btn-sm"
            :data-confirm="actions.archive.confirm"
            @click="archive"
          >{{ actions.archive.label }}</button>
        </div>
      </div>
    </header>

    <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <p class="hud-label">{{ ground_station.details_title }}</p>
          <p class="text-sm text-base-content/70">
            {{ ground_station.description }}
          </p>

          <div class="mt-6 space-y-1">
            <CadenceDataRow
              v-for="detail in ground_station.details"
              :key="detail.label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="detail.label"
            >
              <span class="hud-data-value">{{ detail.value }}</span>
            </CadenceDataRow>
          </div>
        </div>
      </section>

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <p class="hud-label">{{ ground_station.metadata_title }}</p>
          <pre class="overflow-x-auto font-mono text-xs text-base-content/70">{{ ground_station.metadata_json }}</pre>
        </div>
      </section>
    </div>
  </div>
</template>
