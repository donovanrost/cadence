<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue";
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue";
import CadenceHoverTableRow from "./ui/components/CadenceHoverTableRow.vue";

type ProviderRow = {
  id: string;
  display_name: string;
  provider_type: string;
  server_url: string;
  status: "ready" | "attention" | "blocked";
  status_label: string;
  account_binding: string;
  grant_binding: string;
  last_synced_at: string;
  version: string;
  href: string;
};

defineProps<{ rows: ProviderRow[] }>();
</script>

<template>
  <CadenceTableFrame id="mission-providers-table">
    <thead>
      <tr>
        <th class="hud-label">Provider</th>
        <th class="hud-label">Server URL</th>
        <th class="hud-label">Control Plane</th>
        <th class="hud-label">Provider Account</th>
        <th class="hud-label">Mission Grant</th>
        <th class="hud-label">Inventory Sync</th>
        <th class="hud-label">Version</th>
      </tr>
    </thead>
    <tbody id="mission-providers-table-body">
      <CadenceHoverTableRow v-for="row in rows" :id="row.id" :key="row.id">
        <td class="font-medium">
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
            >{{ row.display_name }}</a
          >
          <span class="ml-2 font-mono text-[0.65rem] uppercase tracking-wide text-info">
            {{ row.provider_type }}
          </span>
        </td>
        <td class="max-w-72 truncate font-mono text-sm text-primary/80" :title="row.server_url">
          {{ row.server_url }}
        </td>
        <td>
          <StatusBadge :status="row.status" :label="row.status_label" />
        </td>
        <td class="font-mono text-sm">{{ row.account_binding }}</td>
        <td class="font-mono text-sm">{{ row.grant_binding }}</td>
        <td class="font-mono text-sm">{{ row.last_synced_at }}</td>
        <td class="font-mono text-sm">{{ row.version }}</td>
      </CadenceHoverTableRow>
    </tbody>
  </CadenceTableFrame>
</template>
