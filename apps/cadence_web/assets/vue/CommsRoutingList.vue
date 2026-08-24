<script setup lang="ts">
type RoutingRuleRow = {
  id: string
  display_name: string
  spacecraft_name: string
  purpose_label: string
  direction: string
  transport_name: string
  role: string
  href: string
}

defineProps<{rows: RoutingRuleRow[]}>()
</script>

<template>
  <table id="routing-rules-table" class="table">
    <thead>
      <tr>
        <th class="hud-label">Rule</th>
        <th class="hud-label">Spacecraft</th>
        <th class="hud-label">Purpose</th>
        <th class="hud-label">Direction</th>
        <th class="hud-label">Transport</th>
        <th class="hud-label">Role</th>
      </tr>
    </thead>
    <tbody id="routing-rules">
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
        <td>{{ row.spacecraft_name }}</td>
        <td>{{ row.purpose_label }}</td>
        <td class="font-mono text-sm uppercase text-primary/80">{{ row.direction }}</td>
        <td>{{ row.transport_name }}</td>
        <td class="font-mono text-sm uppercase text-base-content/70">{{ row.role }}</td>
      </tr>
    </tbody>
  </table>
</template>
