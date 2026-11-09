<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import {
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  ApTag,
  formatShort,
  plural,
  type ApColumn,
} from "@/ui";
import ProviderAccountDetail from "./ProviderAccountDetail.vue";
import { fetchProviderAccounts, statusTag } from "./api.ts";

/** Organization › Provider accounts (org admins). Spec: SettingsAuditProviders.md. */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const { state, refetch } = useRemoteQuery(
  () => organization.value?.id ?? null,
  fetchProviderAccounts,
);
const route = useRoute();
const selected = computed(() => {
  const id = route.params.accountId;
  return state.value.status === "ready" && typeof id === "string"
    ? (state.value.value.accounts.find((a) => a.id === id) ?? null)
    : null;
});
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "provider", label: "Provider" },
  { key: "name", label: "Account" },
  { key: "status", label: "Status" },
  { key: "missions", label: "Missions", mono: true, align: "end" },
  { key: "last", label: "Last successful call", mono: true },
  { key: "added", label: "Added" },
];
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
    />
    <ProviderAccountDetail
      v-if="selected && organization && state.status === 'ready'"
      :key="selected.id"
      :organization="organization"
      :account="selected"
      :can-manage="state.value.permissions.includes('provider_accounts.manage')"
      @tested="refetch"
    />
    <ApPanel index="V1" title="Provider accounts" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Provider accounts aren't available in the console yet"
        sentence="This server doesn't serve provider accounts to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading provider accounts…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.accounts.length === 0"
            state="off"
            headline="No provider accounts"
            sentence="A provider account lets missions book passes on a ground network."
          />
          <ApTable
            v-else
            :columns="columns"
            :rows="value.accounts"
            :row-key="(a) => a.id"
            caption="Provider accounts"
          >
            <template #cell-provider="{ row }"
              >{{ row.provider.label
              }}<span class="font-mono text-xs text-text-4"> {{ row.provider.key }}</span></template
            >
            <template #cell-name="{ row }">
              <RouterLink
                :to="{ name: 'org.provider-accounts', params: { accountId: row.id } }"
                class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
                >{{ row.name }}</RouterLink
              >
            </template>
            <template #cell-status="{ row }">
              <ApTag v-bind="statusTag(row)" />
              <span v-if="row.status_detail" class="block text-xs text-text-3">{{
                row.status_detail
              }}</span>
            </template>
            <template #cell-missions="{ row }">{{ row.missions.length }}</template>
            <template #cell-last="{ row }">{{
              row.last_success_at ? formatShort(new Date(row.last_success_at)) : "never"
            }}</template>
            <template #cell-added="{ row }"
              ><span class="text-text-3"
                >{{ formatShort(new Date(row.added_at))
                }}{{ row.added_by ? ` by ${row.added_by.name}` : "" }}</span
              ></template
            >
          </ApTable>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
