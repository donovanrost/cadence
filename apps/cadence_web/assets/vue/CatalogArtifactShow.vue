<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"
import CadenceMenuItem from "./ui/reka/CadenceMenuItem.vue"
import CadenceModalMenu from "./ui/reka/CadenceModalMenu.vue"

type Status = "info" | "ready" | "blocked"

type Artifact = {
  format_key: string
  media_type: string
  content_sha256: string
  uploaded_at: string
  download_href: string
}

type ImportRun = {
  id: string
  actions_id: string
  status: Status
  status_label: string
  started_at: string
  completed_at: string
  href: string
}

defineProps<{
  artifact: Artifact
  runs: ImportRun[]
}>()

const emit = defineEmits<{
  reimport: []
}>()
</script>

<template>
  <div id="catalog-artifact-show-content" class="space-y-6">
    <section
      id="catalog-artifact-metadata-card"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">
        <p class="hud-label">Artifact</p>

        <div class="divide-y divide-base-300">
          <div class="hud-data-row">
            <span class="hud-data-label">Format</span>
            <span class="hud-data-value font-mono text-sm">{{ artifact.format_key }}</span>
          </div>
          <div class="hud-data-row">
            <span class="hud-data-label">Media type</span>
            <span class="hud-data-value font-mono text-sm">{{ artifact.media_type }}</span>
          </div>
          <div class="hud-data-row">
            <span class="hud-data-label">Content SHA-256</span>
            <span class="hud-data-value">
              <span class="break-all font-mono text-xs">{{ artifact.content_sha256 }}</span>
            </span>
          </div>
          <div class="hud-data-row">
            <span class="hud-data-label">Uploaded at</span>
            <span class="hud-data-value">{{ artifact.uploaded_at }}</span>
          </div>
        </div>

        <div class="flex items-center gap-3 pt-2">
          <a
            id="catalog-artifact-download-link"
            :href="artifact.download_href"
            class="btn btn-ghost btn-sm"
          >
            <span class="hero-arrow-down-tray h-4 w-4"></span> Download original
          </a>
          <button
            id="catalog-artifact-reimport-button"
            type="button"
            class="btn btn-primary btn-sm"
            @click="emit('reimport')"
          >
            <span class="hero-arrow-path h-4 w-4"></span> Re-import
          </button>
        </div>
      </div>
    </section>

    <section id="catalog-artifact-runs-section">
      <p class="hud-label mb-2">Import runs</p>

      <section
        v-if="runs.length === 0"
        id="catalog-artifact-runs-empty"
        class="card border border-base-300 bg-base-200"
      >
        <div class="card-body p-6">
          <p class="text-sm text-base-content/60">No runs yet.</p>
        </div>
      </section>

      <section
        v-else
        id="catalog-artifact-runs-card"
        class="card border border-base-300 bg-base-200"
      >
        <div class="card-body p-0">
          <table id="catalog-artifact-runs-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Status</th>
                <th class="hud-label">Started</th>
                <th class="hud-label">Completed</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="catalog-artifact-runs-table-body">
              <tr v-for="run in runs" :id="run.id" :key="run.id">
                <td>
                  <StatusBadge :status="run.status" :label="run.status_label" />
                </td>
                <td class="text-sm text-base-content/70">{{ run.started_at }}</td>
                <td class="text-sm text-base-content/70">{{ run.completed_at }}</td>
                <td class="text-right">
                  <div :id="run.actions_id" class="cadence-overlay">
                    <CadenceModalMenu side="bottom" align="end" :side-offset="4">
                      <template #trigger="{open}">
                        <button
                          :id="`${run.actions_id}-trigger`"
                          type="button"
                          class="btn btn-ghost btn-xs"
                          aria-label="Actions"
                          :aria-controls="open ? `${run.actions_id}-menu` : undefined"
                        >
                          <span class="hero-ellipsis-vertical h-5 w-5"></span>
                        </button>
                      </template>
                      <template #content="{open}">
                        <div
                          :id="`${run.actions_id}-menu`"
                          :aria-labelledby="`${run.actions_id}-trigger`"
                          class="z-50 min-w-40 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
                        >
                          <CadenceMenuItem :active="open">
                            <a
                              :href="run.href"
                              data-phx-link="redirect"
                              data-phx-link-state="push"
                              class="block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200"
                            >View run</a>
                          </CadenceMenuItem>
                        </div>
                      </template>
                    </CadenceModalMenu>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </section>
  </div>
</template>
