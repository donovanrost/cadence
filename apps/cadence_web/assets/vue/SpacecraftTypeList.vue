<script setup lang="ts">
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"

type SpacecraftProfileRow = {
  id: string
  display_name: string
  version: string
  downlink_protocol: string
  uplink_protocol: string
  applications: string
  href: string
}

defineProps<{rows: SpacecraftProfileRow[]}>()
</script>

<template>
  <CadenceTableFrame id="spacecraft-profiles-table">
    <thead>
      <tr>
        <th class="hud-label">Name</th>
        <th class="hud-label">Version</th>
        <th class="hud-label">Downlink</th>
        <th class="hud-label">Uplink</th>
        <th class="hud-label">Applications</th>
      </tr>
    </thead>
    <tbody id="spacecraft-profiles">
      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
      >
        <td class="font-medium">
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
          >{{ row.display_name }}</a>
        </td>
        <td class="font-mono text-sm text-base-content/70">{{ row.version }}</td>
        <td class="font-mono text-sm uppercase text-primary/80">
          {{ row.downlink_protocol }}
        </td>
        <td class="font-mono text-sm uppercase text-primary/80">
          {{ row.uplink_protocol }}
        </td>
        <td class="text-sm text-base-content/70">{{ row.applications }}</td>
      </tr>
    </tbody>
  </CadenceTableFrame>
</template>
