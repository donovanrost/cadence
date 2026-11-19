<script setup lang="ts">
import { ref } from "vue";
import type { SessionOrganization } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, useInPlaceSwap } from "@/ui";
import AccountEditForm from "./AccountEditForm.vue";
import AccountGrants from "./AccountGrants.vue";
import AccountStatusLine from "./AccountStatusLine.vue";
import RemoveAccount from "./RemoveAccount.vue";
import { testAccount, testSentence, type ProviderAccount } from "./api.ts";

/** One provider account: facts, missions using it, and the real credential test. */
const props = defineProps<{
  organization: SessionOrganization;
  account: ProviderAccount;
  canManage: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();
const busy = ref(false);
// a11y A1/A5: Edit swaps to the form (focus its first field); Save and Cancel swap back to Edit.
const manage = ref<HTMLElement | null>(null);
const edit = useInPlaceSwap(manage);
const result = ref<{ tone: "nominal" | "info" | "crit"; text: string } | null>(null);
function saved(text: string) {
  result.value = { tone: "nominal", text };
  void edit.hide();
  emit("changed");
}

async function test() {
  busy.value = true;
  try {
    const r = await testAccount(props.organization.id, props.account.id);
    result.value = r.ok
      ? testSentence(r.value)
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="V2" :title="account.name">
    <template #meta>
      <RouterLink :to="{ name: 'org.provider-accounts' }" class="text-text-3 hover:text-readout"
        >Close</RouterLink
      >
    </template>
    <div class="flex flex-col gap-4">
      <AccountStatusLine :account="account" />
      <div v-if="canManage" ref="manage" class="flex flex-col gap-2">
        <div class="flex gap-2">
          <ApButton :disabled="busy" disabled-reason="Testing…" @click="test"
            >Test reference</ApButton
          >
          <ApButton v-if="!edit.open.value" data-swap-opener variant="ghost" @click="edit.show"
            >Edit</ApButton
          >
        </div>
        <ApCallout v-if="result" :tone="result.tone">{{ result.text }}</ApCallout>
        <AccountEditForm
          v-if="edit.open.value"
          data-swap-editor
          :org-id="organization.id"
          :org-slug="organization.slug"
          :account="account"
          @saved="saved"
          @cancel="edit.hide()"
        />
      </div>
      <AccountGrants
        :organization="organization"
        :account-id="account.id"
        :missions="account.missions"
        @changed="emit('changed')"
      />
      <details>
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-2 font-mono text-sm text-text-3">{{ account.id }}</p>
        <RemoveAccount
          v-if="canManage"
          :org-id="organization.id"
          :account="account"
          @removed="emit('changed')"
        />
      </details>
    </div>
  </ApPanel>
</template>
