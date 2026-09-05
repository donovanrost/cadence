<script setup lang="ts">
import CatalogUploadForm from "./CatalogUploadForm.vue"
import StatusBadge from "./StatusBadge.vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceCompactPageHeaderBodyFrame from "./ui/components/CadenceCompactPageHeaderBodyFrame.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"
import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"
import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"
import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"

type NavigationItem = {
  label: string
  href: string
}

type Navigation = {
  mission: NavigationItem
  catalog: NavigationItem
  current: {label: string}
}

type CatalogDatabase = {
  id: string
  name: string
  slug: string
  description: string
  runtime_usage_summary: string
}

type Revision = {
  id: string
  revision_id: string
  label: string
  number: number
  mission_model_revision_id: string
  href: string
}

type ImportRun = {
  id: string
  run_id: string
  status: {
    value: string
    label: string
    tone: "info" | "ready" | "blocked"
  }
  href: string
}

type CatalogUploadFormProps = InstanceType<typeof CatalogUploadForm>["$props"]

defineProps<{
  database: CatalogDatabase
  navigation: Navigation
  revision_form_open: boolean
  revision_form: CatalogUploadFormProps["form"]
  upload: CatalogUploadFormProps["upload"]
  detected_importer: CatalogUploadFormProps["detected_importer"]
  submit_disabled: boolean
  revisions: Revision[]
  import_runs: ImportRun[]
}>()

const emit = defineEmits<{
  "toggle-revision-form": [payload: Record<string, never>]
  validate: [payload: Record<string, Record<string, string>>]
  save: []
  "cancel-upload": [payload: {ref: string}]
}>()
</script>

<template>
  <CadenceCollapsible
    content-id="catalog-revision-upload-slot"
    :open="revision_form_open"
    @request-change="emit('toggle-revision-form', {})"
  >
    <div id="catalog-database-show-surface" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <CadenceCompactPageHeaderBodyFrame>
        <template #content>
          <CadenceBreadcrumbs>
            <a
              :href="navigation.mission.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="transition-colors hover:text-primary"
              >{{ navigation.mission.label }}</a
            >
            <span class="text-base-content/20" aria-hidden="true">/</span>
            <a
              :href="navigation.catalog.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="transition-colors hover:text-primary"
              >{{ navigation.catalog.label }}</a
            >
            <span class="text-base-content/20" aria-hidden="true">/</span>
            <span class="text-primary/90">{{ navigation.current.label }}</span>
          </CadenceBreadcrumbs>

          <h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">
            {{ database.name }}
            <span class="ml-3 font-mono text-base text-base-content/60">{{ database.slug }}</span>
          </h1>
        </template>

        <template #actions>
          <CadenceCollapsibleTrigger>
            <button
              id="add-revision-toggle"
              type="button"
              class="btn"
              :class="revision_form_open ? 'btn-ghost' : 'btn-primary'"
            >
              {{ revision_form_open ? "Cancel" : "+ Add revision" }}
            </button>
          </CadenceCollapsibleTrigger>
        </template>
      </CadenceCompactPageHeaderBodyFrame>
    </CadencePageHeaderFrame>

    <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <CadenceCard class="card border border-base-300 bg-base-200 lg:col-span-2" body-class="card-body p-6">
          <p class="hud-label">Database</p>
          <p class="mt-2 text-sm text-base-content/70">{{ database.description }}</p>
      </CadenceCard>

      <CadenceCard class="card border border-base-300 bg-base-200" body-class="card-body p-6">
          <p class="hud-label">Runtime usage</p>
          <p id="catalog-runtime-usage-summary" class="mt-2 text-sm text-base-content/60">
            {{ database.runtime_usage_summary }}
          </p>
      </CadenceCard>
    </div>

    <CadenceCollapsibleContent>
      <div>
        <CatalogUploadForm
          :form="revision_form"
          :upload="upload"
          :detected_importer="detected_importer"
          :submit_disabled="submit_disabled"
          @validate="emit('validate', $event)"
          @save="emit('save')"
          @cancel-upload="emit('cancel-upload', $event)"
        />
      </div>
    </CadenceCollapsibleContent>

    <CadenceCard id="catalog-revision-history" class="card border border-base-300 bg-base-200" body-class="card-body p-6">
        <p class="hud-label">Revision history</p>
        <p
          v-if="revisions.length === 0"
          id="catalog-revisions-empty-state"
          class="text-sm text-base-content/60"
        >
          No revisions yet.
        </p>
        <CadenceTableFrame v-else id="catalog-revisions-table">
          <thead>
            <tr>
              <th class="hud-label">Revision</th>
              <th class="hud-label">Mission Model</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody id="catalog-revisions-table-body">
            <tr v-for="revision in revisions" :id="revision.id" :key="revision.revision_id">
              <td>
                <p class="font-medium">{{ revision.label }}</p>
                <p class="font-mono text-xs text-base-content/60">#{{ revision.number }}</p>
              </td>
              <td>
                <span class="font-mono text-xs">{{ revision.mission_model_revision_id }}</span>
              </td>
              <td class="text-right">
                <a
                  :href="revision.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-ghost btn-xs"
                  >View revision</a
                >
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
    </CadenceCard>

    <CadenceCard id="catalog-import-attempts" class="card border border-base-300 bg-base-200" body-class="card-body p-6">
        <p class="hud-label">Import attempts</p>
        <p
          v-if="import_runs.length === 0"
          id="catalog-import-runs-empty-state"
          class="text-sm text-base-content/60"
        >
          No import attempts yet.
        </p>
        <CadenceTableFrame v-else id="catalog-import-runs-table">
          <thead>
            <tr>
              <th class="hud-label">Status</th>
              <th class="hud-label">Run</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody id="catalog-import-runs-table-body">
            <tr v-for="run in import_runs" :id="run.id" :key="run.run_id">
              <td>
                <StatusBadge :status="run.status.tone" :label="run.status.label" />
              </td>
              <td class="font-mono text-xs text-base-content/60">{{ run.run_id }}</td>
              <td class="text-right">
                <a
                  :href="run.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-ghost btn-xs"
                  >View run</a
                >
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
    </CadenceCard>
    </div>
  </CadenceCollapsible>
</template>
