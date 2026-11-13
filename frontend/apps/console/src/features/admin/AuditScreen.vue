<script setup lang="ts">
import { ref, watch } from "vue";
import { actorName, useRemoteQuery } from "@/api";
import {
  ApButton,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  formatShort,
  type ApColumn,
} from "@/ui";
import { fetchPlatformAudit, type PlatformAuditEvent } from "./api.ts";

/**
 * Admin › Audit (api-ops): organizations created, cross-org invitations, service identities issued
 * or revoked, admin mode on and off. Events with an organization also show in that org's Audit.
 */
const first = useRemoteQuery(() => ({ after: null }), fetchPlatformAudit);
const older = ref<readonly PlatformAuditEvent[]>([]);
const cursor = ref<string | null>(null);
const loading = ref(false);
watch(first.state, (s) => {
  if (s.status !== "ready") return;
  older.value = [];
  cursor.value = s.value.next;
});
async function loadOlder() {
  if (!cursor.value || loading.value) return;
  loading.value = true;
  try {
    const r = await fetchPlatformAudit({ after: cursor.value }, new AbortController().signal);
    if (!r.ok) return;
    older.value = [...older.value, ...r.value.events];
    cursor.value = r.value.next;
  } finally {
    loading.value = false;
  }
}
const columns: readonly ApColumn[] = [
  { key: "at", label: "Time", mono: true },
  { key: "actor", label: "Who" },
  { key: "action", label: "What" },
  { key: "org", label: "Organization" },
];
</script>

<template>
  <ApPageHeader label="Platform admin · audit" title="Audit" size="reading" />
  <ApPanel index="A1" title="Platform events" flush>
    <ApRemote :state="first.state.value" loading-label="Loading audit…" @retry="first.refetch">
      <template #default="{ value }">
        <ApEmptyState v-if="value.events.length === 0" headline="Nothing recorded yet" />
        <ApTable
          v-else
          :columns="columns"
          :rows="[...value.events, ...older]"
          :row-key="(e) => e.id"
          caption="Platform audit"
        >
          <template #cell-at="{ row }">{{ formatShort(new Date(row.at)) }}</template>
          <template #cell-actor="{ row }">{{ actorName(row.actor) }}</template>
          <template #cell-action="{ row }"
            >{{ row.action
            }}<span v-if="row.target" class="text-text-3"> · {{ row.target.label }}</span></template
          >
          <template #cell-org="{ row }">
            <RouterLink
              v-if="row.organization"
              :to="{ name: 'admin.organization', params: { orgId: row.organization.id } }"
              class="text-readout hover:underline"
              >{{ row.organization.name }}</RouterLink
            >
            <span v-else class="text-text-3">Platform</span>
          </template>
        </ApTable>
        <div v-if="cursor" class="border-t border-hairline px-4 py-2.5">
          <ApButton size="compact" :disabled="loading" disabled-reason="Loading…" @click="loadOlder"
            >Older</ApButton
          >
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
