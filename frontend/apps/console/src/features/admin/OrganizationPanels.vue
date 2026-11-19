<script setup lang="ts">
import { roleText } from "@/api";
import { ApPanel, ApTable, formatShort, plural, type ApColumn } from "@/ui";
import type { AdminOrganizationDetail } from "./api.ts";
import InvitationsPanel from "./InvitationsPanel.vue";

/** The organization's Members (read-only) · Invitations (Withdraw) · Missions (read-only). */
defineProps<{ detail: AdminOrganizationDetail }>();
const emit = defineEmits<{ changed: [note: { tone: "nominal" | "crit"; text: string }] }>();
const members: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "email", label: "Email", mono: true },
  { key: "role", label: "Role" },
];
const missions: readonly ApColumn[] = [
  { key: "name", label: "Mission" },
  { key: "created", label: "Created", mono: true },
];
</script>

<template>
  <ApPanel index="O2" title="Members" :meta="plural(detail.members.length, 'member')" flush>
    <ApTable
      :columns="members"
      :rows="detail.members"
      :row-key="(m) => m.user_id"
      caption="Members"
    >
      <template #cell-name="{ row }">{{ row.name ?? "—" }}</template>
      <template #cell-role="{ row }">{{ roleText(row.role) }}</template>
    </ApTable>
  </ApPanel>
  <InvitationsPanel
    :org-id="detail.organization.id"
    :invitations="detail.invitations"
    @changed="emit('changed', $event)"
  />
  <ApPanel index="O4" title="Missions" :meta="plural(detail.missions.length, 'mission')" flush>
    <ApTable :columns="missions" :rows="detail.missions" :row-key="(m) => m.id" caption="Missions">
      <template #cell-created="{ row }">{{
        row.created_at ? formatShort(new Date(row.created_at)) : "—"
      }}</template>
    </ApTable>
  </ApPanel>
</template>
