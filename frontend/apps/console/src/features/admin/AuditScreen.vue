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
import AuditAction from "./AuditAction.vue";
import AuditOrg from "./AuditOrg.vue";
import { fetchPlatformAudit, type PlatformAuditEvent, type UnreadableAuditEvent } from "./api.ts";

/**
 * Admin › Audit (api-ops): organizations created, cross-org invitations, service identities issued
 * or revoked, admin mode on and off. Events with an organization also show in that org's Audit.
 */
const first = useRemoteQuery(() => ({ after: null }), fetchPlatformAudit);
type Row = PlatformAuditEvent | UnreadableAuditEvent;
const older = ref<readonly Row[]>([]);
/** lead 11-13: an event the console can't read keeps its place as "Unreadable entry". */
const readable = (r: Row): PlatformAuditEvent | null => ("unreadable" in r ? null : r);
const atText = (r: Row) => {
  const e = readable(r);
  return e ? formatShort(new Date(e.at)) : "—";
};
const whoText = (r: Row) => {
  const e = readable(r);
  return e ? actorName(e.actor) : "";
};
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
          <template #cell-at="{ row }">{{ atText(row) }}</template>
          <template #cell-actor="{ row }">{{ whoText(row) }}</template>
          <template #cell-action="{ row }"
            ><AuditAction :event="readable(row)" :raw="'raw' in row ? row.raw : []"
          /></template>
          <template #cell-org="{ row }"><AuditOrg :event="readable(row)" /></template>
        </ApTable>
        <div v-if="cursor || older.length > 0" class="border-t border-hairline px-4 py-2.5">
          <ApButton
            size="compact"
            :disabled="loading || !cursor"
            :disabled-reason="loading ? 'Loading…' : 'No older events'"
            @click="loadOlder"
            >Older</ApButton
          >
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
