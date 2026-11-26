<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { failureOutcome } from "@/features/changes/index.ts";
import { roleText } from "@/api";
import { ApButton, ApPanel, ApTable, formatShort, plural, type ApColumn } from "@/ui";
import { withdrawInvitation, type AdminOrganizationDetail } from "./api.ts";

/** The organization's invitations (Admin.md), each pending one with Withdraw. */
const props = defineProps<{
  orgId: OrganizationId;
  invitations: AdminOrganizationDetail["invitations"];
}>();
const emit = defineEmits<{ changed: [note: { tone: "nominal" | "crit"; text: string }] }>();
const columns: readonly ApColumn[] = [
  { key: "email", label: "Email", mono: true },
  { key: "role", label: "Role" },
  { key: "by", label: "Invited" },
  { key: "state", label: "State" },
  { key: "actions", label: "", align: "end" },
];
const stateWord = { pending: "Pending", expired: "Expired", unrecognized: "Not known" } as const;
async function withdraw(id: string, email: string) {
  const r = await withdrawInvitation(props.orgId, id);
  emit(
    "changed",
    r.ok
      ? { tone: "nominal", text: `Withdrew the invitation to ${email}.` }
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence },
  );
}
</script>

<template>
  <ApPanel index="O3" title="Invitations" :meta="plural(invitations.length, 'invitation')" flush>
    <ApTable :columns="columns" :rows="invitations" :row-key="(i) => i.id" caption="Invitations">
      <template #cell-role="{ row }">{{ roleText(row.role) }}</template>
      <template #cell-by="{ row }"
        >{{ row.invited_by?.name ?? "Not recorded" }} ·
        {{ formatShort(new Date(row.invited_at)) }}</template
      >
      <template #cell-state="{ row }">{{ stateWord[row.state] }}</template>
      <template #cell-actions="{ row }">
        <ApButton
          v-if="row.state === 'pending'"
          size="compact"
          variant="ghost"
          @click="withdraw(row.id, row.email)"
          >Withdraw</ApButton
        >
      </template>
    </ApTable>
  </ApPanel>
</template>
