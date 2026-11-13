<script setup lang="ts">
import { ref } from "vue";
import { ApButton } from "@/ui";
import ReasonSheet from "./ReasonSheet.vue";
import { accountFailure, revokeCredential, type AccountDetail, type AccountKey } from "./grants.ts";

/** The account's credential reference and, for org admins, Revoke credential… (L13). */
const props = defineProps<{ accountKey: AccountKey; detail: AccountDetail; canManage: boolean }>();
const emit = defineEmits<{ done: [text: string] }>();
const sheet = ref<InstanceType<typeof ReasonSheet> | null>(null);
async function revoke(reason: string) {
  const r = await revokeCredential(
    props.accountKey,
    props.detail.account.credential.version,
    reason,
  );
  sheet.value?.settle(r.ok ? null : accountFailure(r.error));
  if (r.ok)
    emit("done", "Credential revoked. Point the account at a new reference to use it again.");
}
</script>

<template>
  <p class="m-0 flex flex-wrap items-center gap-2 text-sm text-text-2">
    Credential <span class="font-mono">{{ detail.account.credential.ref }}</span> ·
    {{ detail.account.credential.status === "active" ? "active" : "revoked" }}
    <ApButton
      v-if="canManage && detail.account.credential.status === 'active'"
      size="compact"
      variant="danger"
      @click="sheet?.open()"
      >Revoke credential…</ApButton
    >
  </p>
  <ReasonSheet
    ref="sheet"
    title="Revoke credential"
    confirm="Revoke credential"
    sentence="Every mission provider on this account stops working until you point the account at a new reference."
    @confirm="revoke"
  />
</template>
