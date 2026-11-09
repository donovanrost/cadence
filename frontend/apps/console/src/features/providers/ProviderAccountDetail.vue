<script setup lang="ts">
import { ref } from "vue";
import type { SessionOrganization } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, ApTag, formatShort } from "@/ui";
import { statusTag, testAccount, type ProviderAccount } from "./api.ts";

/** One provider account: facts, missions using it, and the real credential test. */
const props = defineProps<{
  organization: SessionOrganization;
  account: ProviderAccount;
  canManage: boolean;
}>();
const emit = defineEmits<{ tested: [] }>();
const busy = ref(false);
const result = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);

async function test() {
  busy.value = true;
  try {
    const r = await testAccount(props.organization.id, props.account.id);
    result.value = r.ok
      ? { tone: r.value.ok ? "nominal" : "crit", text: r.value.message }
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
    emit("tested");
  } finally {
    busy.value = false;
  }
}
const slugOf = (id: string) => props.organization.missions.find((m) => m.id === id)?.slug;
</script>

<template>
  <ApPanel index="V2" :title="account.name">
    <template #meta>
      <RouterLink :to="{ name: 'org.provider-accounts' }" class="text-text-3 hover:text-readout"
        >Close</RouterLink
      >
    </template>
    <div class="flex flex-col gap-4">
      <div class="flex flex-wrap items-center gap-3">
        <ApTag v-bind="statusTag(account)" />
        <span v-if="account.status_detail" class="text-sm text-text-3">{{
          account.status_detail
        }}</span>
        <span class="font-mono text-sm text-text-3"
          >Last success
          {{
            account.last_success_at ? formatShort(new Date(account.last_success_at)) : "never"
          }}</span
        >
      </div>
      <div v-if="canManage" class="flex flex-col gap-2">
        <div>
          <ApButton :disabled="busy" disabled-reason="Testing…" @click="test"
            >Test connection</ApButton
          >
        </div>
        <ApCallout v-if="result" :tone="result.tone">{{ result.text }}</ApCallout>
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="ap-label">Missions using it</span>
        <p v-if="account.missions.length === 0" class="m-0 text-sm text-text-3">
          No mission uses this account yet.
        </p>
        <ul v-else class="m-0 flex list-none flex-col gap-1 p-0">
          <li v-for="m in account.missions" :key="m.id">
            <RouterLink
              v-if="slugOf(m.id)"
              :to="{
                name: 'setup.stations.providers',
                params: { org: organization.slug, mission: slugOf(m.id) },
              }"
              class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              >{{ m.name }}</RouterLink
            >
            <span v-else>{{ m.name }}</span>
          </li>
        </ul>
      </div>
      <details>
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-2 font-mono text-sm text-text-3">{{ account.id }}</p>
        <p class="m-0 mt-1 text-sm text-text-3">Accounts can't be removed yet.</p>
      </details>
    </div>
  </ApPanel>
</template>
