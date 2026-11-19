<script setup lang="ts">
import type { RemoteState } from "@/api";
import { ApEmptyState, ApPanel, ApRemote } from "@/ui";
import AccountsTable from "./AccountsTable.vue";
import type { ProviderAccounts } from "./api.ts";

/** V1 · Provider accounts: the table (Name-cell link to the detail). */
defineProps<{ state: RemoteState<ProviderAccounts>; notProvided: boolean }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <ApPanel index="V1" title="Provider accounts" flush>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Provider accounts aren't available in the console yet"
      sentence="This server doesn't serve provider accounts to the console yet."
    />
    <ApRemote
      forbidden-text="Org admins see this."
      v-else
      :state="state"
      loading-label="Loading provider accounts…"
      @retry="$emit('retry')"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.accounts.length === 0"
          state="off"
          headline="No provider accounts"
          sentence="A provider account lets missions book passes on a ground network."
        />
        <AccountsTable v-else :accounts="value.accounts" />
      </template>
    </ApRemote>
  </ApPanel>
</template>
