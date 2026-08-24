<script setup lang="ts">
type OrganizationRow = {
  id: string
  display_name: string
  slug: string
  href: string
}

defineProps<{rows: OrganizationRow[]}>()
</script>

<template>
  <table id="admin-orgs-table" class="table">
    <thead>
      <tr>
        <th class="hud-label">Name</th>
        <th class="hud-label">Slug</th>
      </tr>
    </thead>
    <tbody id="admin-orgs-table-body">
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
        <td class="font-mono text-sm">{{ row.slug }}</td>
      </tr>
    </tbody>
  </table>
</template>
