<script setup lang="ts">
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"
import CadenceHoverTableRow from "./ui/components/CadenceHoverTableRow.vue"

type OrganizationRow = {
  id: string
  display_name: string
  slug: string
  href: string
}

defineProps<{rows: OrganizationRow[]}>()
</script>

<template>
  <CadenceTableFrame id="admin-orgs-table">
    <thead>
      <tr>
        <th class="hud-label">Name</th>
        <th class="hud-label">Slug</th>
      </tr>
    </thead>
    <tbody id="admin-orgs-table-body">
      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >
        <td class="font-medium">
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
          >{{ row.display_name }}</a>
        </td>
        <td class="font-mono text-sm">{{ row.slug }}</td>
      </CadenceHoverTableRow>
    </tbody>
  </CadenceTableFrame>
</template>
