<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRemoteQuery, type SessionOrganization } from "@/api";
import { ApButton, ApCallout, refocusFirst } from "@/ui";
import AccountCredential from "./AccountCredential.vue";
import AccountGrantsTable from "./AccountGrantsTable.vue";
import AccountMissions from "./AccountMissions.vue";
import GrantMissionSheet from "./GrantMissionSheet.vue";
import ReasonSheet from "./ReasonSheet.vue";
import {
  accountFailure,
  fetchAccountDetail,
  PA2_LIVE,
  revokedLine,
  revokeGrant,
  type AccountGrant,
} from "./grants.ts";

/** L13: which missions may use the account (grants), and the credential's revoke. */
const props = defineProps<{
  organization: SessionOrganization;
  accountId: string;
  missions: readonly Readonly<{ id: string; name: string }>[];
}>();
const emit = defineEmits<{ changed: [] }>();
const key = computed(() => ({ orgId: props.organization.id, accountId: props.accountId }));
const detail = useRemoteQuery(() => (PA2_LIVE ? key.value : null), fetchAccountDetail);
const ready = computed(() =>
  detail.state.value.status === "ready" ? detail.state.value.value : null,
);
const canManage = computed(
  () => ready.value?.permissions.includes("provider_accounts.manage") ?? false,
);
const note = ref<string | null>(null);
const grantSheet = ref<InstanceType<typeof GrantMissionSheet> | null>(null);
const revokeSheet = ref<InstanceType<typeof ReasonSheet> | null>(null);
const picked = ref<AccountGrant | null>(null);
// a11y A5: a revoke's refetch removes its opener (the row's Revoke…, Revoke credential…) after the
// sheet has returned focus to it; once the account re-reads, land on the note instead.
let settleOnNote = false;
watch(
  () => detail.state.value,
  () => {
    if (!settleOnNote) return;
    settleOnNote = false;
    refocusFirst(document.querySelector<HTMLElement>("[data-account-note]"));
  },
  { flush: "post" },
);
function done(text: string) {
  note.value = text;
  settleOnNote = true;
  detail.refetch();
  emit("changed");
}
async function revoke(reason: string) {
  if (!picked.value) return;
  const r = await revokeGrant(key.value, picked.value, reason);
  revokeSheet.value?.settle(r.ok ? null : accountFailure(r.error));
  if (r.ok) done(revokedLine(r.value.flagged_reservations));
}
</script>

<template>
  <!-- Until api-ops serves the account detail (PA2), the missions list from PA1 stands in. -->
  <AccountMissions v-if="!ready" :organization="organization" :missions="missions" />
  <div v-else class="flex flex-col gap-2">
    <div class="flex items-center justify-between gap-2">
      <span class="ap-label">Granted to</span>
      <ApButton v-if="canManage" size="compact" @click="grantSheet?.open()"
        >Grant to a mission…</ApButton
      >
    </div>
    <AccountGrantsTable
      :grants="ready.grants"
      :can-manage="canManage"
      @revoke="(g) => ((picked = g), revokeSheet?.open())"
    />
    <ApCallout v-if="note" data-account-note tone="nominal">{{ note }}</ApCallout>
    <AccountCredential :account-key="key" :detail="ready" :can-manage="canManage" @done="done" />
    <GrantMissionSheet
      ref="grantSheet"
      :organization="organization"
      :detail="ready"
      @granted="done('Granted.')"
    />
    <ReasonSheet
      ref="revokeSheet"
      title="Revoke grant"
      confirm="Revoke"
      sentence="The mission stops booking through this account. Open bookings that use it are flagged for an operator's review."
      @confirm="revoke"
    />
  </div>
</template>
