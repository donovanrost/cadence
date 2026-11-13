<script setup lang="ts">
import { ref } from "vue";
import { useRemoteQuery } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import {
  ApButton,
  ApCallout,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  formatShort,
  type ApColumn,
} from "@/ui";
import { fetchServiceIdentities, revokeServiceIdentity, type AdminServiceIdentity } from "./api.ts";
import ServiceIdentityIssue from "./ServiceIdentityIssue.vue";
import PlatformCaption from "./PlatformCaption.vue";
import IdentityActions from "./IdentityActions.vue";

/** Admin › Service identities (Admin.md): Name · Organization · Created · Last used · Revoke; Issue. */
// A constant key: a null key pauses useRemoteQuery, and this list is every organization's (qa 11-13).
const list = useRemoteQuery(
  () => ({ scope: "platform" as const }),
  (_key, signal) => fetchServiceIdentities(null, signal),
);
const issue = ref<InstanceType<typeof ServiceIdentityIssue> | null>(null);
const note = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "org", label: "Organization" },
  { key: "may", label: "May" },
  { key: "created", label: "Created" },
  { key: "used", label: "Last used", mono: true },
  { key: "actions", label: "", align: "end" },
];
async function revoke(s: AdminServiceIdentity) {
  const r = await revokeServiceIdentity(s.id, s.organization.id);
  note.value = r.ok
    ? { tone: "nominal", text: `Revoked ${s.name}. Anything using its token stops working now.` }
    : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
  list.refetch();
}
</script>

<template>
  <ApPageHeader
    label="Platform admin · service identities"
    title="Service identities"
    size="reading"
  >
    <ApButton v-if="list.state.value.status === 'ready'" variant="primary" @click="issue?.open()"
      >Issue</ApButton
    >
  </ApPageHeader>
  <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
  <ApPanel index="S1" title="Service identities" flush>
    <ApRemote
      :state="list.state.value"
      loading-label="Loading service identities…"
      @retry="list.refetch"
    >
      <template #default="{ value }">
        <ApTable
          :columns="columns"
          :rows="value.service_identities"
          :row-key="(s) => s.id"
          caption="Service identities"
        >
          <template #cell-org="{ row }">{{ row.organization.name }}</template>
          <template #cell-may="{ row }"
            >{{ row.capabilities.map((c) => c.label).join(", ")
            }}<template v-if="row.mission"> · {{ row.mission.name }}</template></template
          >
          <template #cell-created="{ row }"
            >{{ row.created_by?.name ?? "Not recorded" }} ·
            {{ formatShort(new Date(row.created_at)) }}</template
          >
          <template #cell-used="{ row }">{{
            row.last_used_at ? formatShort(new Date(row.last_used_at)) : "Not tracked yet"
          }}</template>
          <template #cell-actions="{ row }"
            ><IdentityActions :identity="row" @rotated="list.refetch" @revoke="revoke(row)"
          /></template>
        </ApTable>
        <ServiceIdentityIssue
          ref="issue"
          :capabilities="value.capabilities"
          @issued="list.refetch"
        />
      </template>
    </ApRemote>
  </ApPanel>
  <PlatformCaption />
</template>
