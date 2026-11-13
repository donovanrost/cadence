<script setup lang="ts">
import { ApTable, ApTag, formatShort, type ApColumn } from "@/ui";
import { invitationTag, roleLabel, type Invitation } from "./api.ts";

/** Invitations tab. */
defineProps<{ rows: readonly Invitation[] }>();
const columns: readonly ApColumn[] = [
  { key: "email", label: "Email", mono: true },
  { key: "role", label: "Role" },
  { key: "by", label: "Invited by" },
  { key: "sent", label: "Sent", mono: true },
  { key: "status", label: "Status" },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(i) => i.id" caption="Invitations">
    <template #cell-email="{ row }">
      <RouterLink
        :to="{ name: 'org.people.invitation', params: { invitationId: row.id } }"
        class="text-readout hover:underline"
        >{{ row.email }}</RouterLink
      >
    </template>
    <template #cell-role="{ row }">{{ roleLabel(row.role) }}</template>
    <template #cell-by="{ row }">{{ row.invited_by?.name ?? "—" }}</template>
    <template #cell-sent="{ row }">{{ formatShort(new Date(row.sent_at)) }}</template>
    <template #cell-status="{ row }">
      <ApTag :state="invitationTag(row.status).state" :label="invitationTag(row.status).label" />
    </template>
  </ApTable>
</template>
