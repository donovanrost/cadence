<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { canAdministerOrganization, useConsoleScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, plural } from "@/ui";
import AddAccountPanel from "./AddAccountPanel.vue";
import AccountHistory from "./AccountHistory.vue";
import AccountsPanel from "./AccountsPanel.vue";
import ProviderAccountDetail from "./ProviderAccountDetail.vue";
import { fetchProviderAccounts } from "./api.ts";

/** Organization › Provider accounts (org admins). Spec: SettingsAuditProviders.md. */
const history = ref<InstanceType<typeof AccountHistory> | null>(null);
/** An edit makes a new version: refresh the list and the history together. */
function onChanged() {
  refetch();
  history.value?.refetch();
}
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
/** Org admins only: a member never fires the read (qa: a 403 trips the e2e diagnostics guard). */
const session = useSession();
const isAdmin = computed(() =>
  organization.value ? canAdministerOrganization(session, organization.value) : false,
);
const { state, refetch } = useRemoteQuery(
  () => (isAdmin.value ? (organization.value?.id ?? null) : null),
  fetchProviderAccounts,
);
const route = useRoute("org.provider-accounts");
const adding = computed(() => route.params.accountId === "new");
const selected = computed(() => {
  const id = route.params.accountId;
  return state.value.status === "ready" && typeof id === "string"
    ? (state.value.value.accounts.find((a) => a.id === id) ?? null)
    : null;
});
const canManage = computed(
  () =>
    state.value.status === "ready" &&
    state.value.value.permissions.includes("provider_accounts.manage"),
);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · organization`"
      :title="
        state.status === 'ready'
          ? plural(state.value.accounts.length, 'provider account')
          : 'Provider accounts'
      "
      size="reading"
    >
      <ApButton
        v-if="canManage && !adding"
        variant="primary"
        :to="{ name: 'org.provider-accounts', params: { accountId: 'new' } }"
        >Add provider account</ApButton
      >
    </ApPageHeader>
    <ProviderAccountDetail
      v-if="selected && organization && state.status === 'ready'"
      :key="selected.id"
      :organization="organization"
      :account="selected"
      :can-manage="canManage"
      @changed="onChanged"
    />
    <AccountHistory
      v-if="selected && organization && state.status === 'ready'"
      :key="`history-${selected.id}`"
      ref="history"
      :org-id="organization.id"
      :account-id="selected.id"
    />
    <AddAccountPanel
      v-if="adding && canManage && organization && state.status === 'ready'"
      :organization="organization"
      :adapters="state.value.adapters"
      @added="refetch"
    />
    <AccountsPanel v-if="isAdmin" :state="state" :not-provided="notProvided" @retry="refetch" />
    <ApEmptyState v-else state="off" headline="Org admins see this." />
  </div>
</template>
