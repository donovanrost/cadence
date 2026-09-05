<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"

type MissionRow = {
  id: string
  display_name: string
  slug: string
  spacecraft_count: number
  status: "info" | "ready" | "attention"
  status_label: string
  href: string
}

defineProps<{rows: MissionRow[]}>()

</script>

<template>
  <CadenceTableFrame id="mission-list-table">
    <thead>
      <tr>
        <th class="hud-label">Mission</th>
        <th class="hud-label">Slug</th>
        <th class="hud-label text-right">Spacecraft</th>
        <th class="hud-label">Status</th>
      </tr>
    </thead>
    <tbody id="mission-list-table-body">
      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
      >
        <td class="font-medium">
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
          >{{ row.display_name }}</a>
        </td>
        <td class="font-mono text-sm text-primary/80">{{ row.slug }}</td>
        <td class="text-right font-mono text-sm">{{ row.spacecraft_count }}</td>
        <td>
          <StatusBadge :status="row.status" :label="row.status_label" />
        </td>
      </tr>
    </tbody>
  </CadenceTableFrame>
</template>
