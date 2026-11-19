<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import ReasonSheet from "./ReasonSheet.vue";
import { accountFailure, revokeCredential, type AccountDetail, type AccountKey } from "./grants.ts";

/** The account's credential reference and, for org admins, Revoke credential… (L13). */
const props = defineProps<{ accountKey: AccountKey; detail: AccountDetail; canManage: boolean }>();
const emit = defineEmits<{ done: [text: string] }>();
const sheet = ref<InstanceType<typeof ReasonSheet> | null>(null);
const statusWord: Readonly<Record<AccountDetail["account"]["credential"]["status"], string>> = {
  active: "active",
  revoked: "revoked",
  missing: "missing",
  unrecognized: "unknown",
};
async function revoke(reason: string) {
  const version = props.detail.account.credential.version;
  if (version === null) return;
  const r = await revokeCredential(props.accountKey, version, reason);
  sheet.value?.settle(r.ok ? null : accountFailure(r.error));
  if (r.ok)
    emit("done", "Credential revoked. Point the account at a new reference to use it again.");
}
</script>

<template>
  <p class="m-0 flex flex-wrap items-center gap-2 text-sm text-text-2">
    Credential <span class="font-mono">{{ detail.account.credential.ref }}</span> ·
    {{ statusWord[detail.account.credential.status] }}
    <ApButton
      v-if="canManage && detail.account.credential.status === 'active'"
      size="compact"
      variant="danger"
      @click="sheet?.open()"
      >Revoke credential…</ApButton
    >
  </p>
  <ApCallout v-if="detail.account.credential.status === 'missing'" tone="caution"
    >No credential is registered under this reference. Point the account at a registered
    one.</ApCallout
  >
  <ReasonSheet
    ref="sheet"
    title="Revoke credential"
    confirm="Revoke credential"
    sentence="Every mission provider on this account stops working until you point the account at a new reference."
    @confirm="revoke"
  />
</template>
