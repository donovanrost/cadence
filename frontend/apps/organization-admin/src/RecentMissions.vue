<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"

type MissionRow = {
  id: string
  display_name: string
  slug: string
  status: "info" | "ready" | "attention"
  status_label: string
  href: string
}

defineProps<{rows: MissionRow[]}>()

</script>

<template>
  <ul id="organization-recent-missions-list" class="mt-5 divide-y divide-base-300">
    <li
      v-for="row in rows"
      :id="row.id"
      :key="row.id"
      class="py-3"
    >
      <a
        :href="row.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="flex items-center justify-between gap-4 hover:text-primary"
      >
        <div>
          <p class="font-medium">{{ row.display_name }}</p>
          <p class="font-mono text-xs text-base-content/60">{{ row.slug }}</p>
        </div>
        <StatusBadge :status="row.status" :label="row.status_label" />
      </a>
    </li>
  </ul>
</template>
