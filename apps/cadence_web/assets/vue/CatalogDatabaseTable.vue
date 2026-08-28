<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"
import CadenceMenuItem from "./ui/reka/CadenceMenuItem.vue"
import CadenceModalMenu from "./ui/reka/CadenceModalMenu.vue"

type Status = "info" | "ready" | "blocked"

type Revision = {
  label: string
  href: string
}

type ImportRun = {
  status: Status
  status_label: string
  href: string
}

type DatabaseRow = {
  id: string
  actions_id: string
  name: string
  slug: string
  href: string
  latest_revision: Revision | null
  latest_import: ImportRun | null
}

defineProps<{rows: DatabaseRow[]}>()

</script>

<template>
  <CadenceTableFrame id="catalog-databases-table">
    <thead>
      <tr>
        <th>Database</th>
        <th>Latest revision</th>
        <th>Latest import</th>
        <th>Runtime usage</th>
        <th class="text-right">Actions</th>
      </tr>
    </thead>
    <tbody>
      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
      >
        <td>
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="font-medium hover:underline"
          >{{ row.name }}</a>
          <p class="font-mono text-xs text-base-content/60">{{ row.slug }}</p>
        </td>
        <td>
          <a
            v-if="row.latest_revision"
            :href="row.latest_revision.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="font-mono text-sm hover:underline"
          >{{ row.latest_revision.label }}</a>
          <span v-else class="text-xs text-base-content/50">No revisions</span>
        </td>
        <td>
          <a
            v-if="row.latest_import"
            :href="row.latest_import.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="inline-flex"
          >
            <StatusBadge
              :status="row.latest_import.status"
              :label="row.latest_import.status_label"
            />
          </a>
          <span v-else class="text-xs text-base-content/50">—</span>
        </td>
        <td>
          <span class="text-xs text-base-content/60" id="catalog-runtime-usage-summary">
            No runtime bindings yet
          </span>
        </td>
        <td class="text-right">
          <CadenceModalMenu side="bottom" align="end" :side-offset="4">
            <template #trigger>
              <button
                :id="row.actions_id"
                class="btn btn-ghost btn-sm"
                type="button"
                aria-label="Database actions"
              >
                <span class="hero-ellipsis-vertical h-4 w-4"></span>
              </button>
            </template>
            <template #content="{open}">
              <div
                :aria-labelledby="row.actions_id"
                class="z-50 min-w-40 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
              >
                <CadenceMenuItem :active="open">
                  <a
                    :href="row.href"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200"
                  >View database</a>
                </CadenceMenuItem>
              </div>
            </template>
          </CadenceModalMenu>
        </td>
      </tr>
    </tbody>
  </CadenceTableFrame>
</template>
