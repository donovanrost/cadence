<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { decoders } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApInlineConfirm } from "@/ui";
import { removeAccount, type ProviderAccount } from "./api.ts";

/**
 * Remove (archive) an account; blocked with the reason while missions use it. The confirm is the
 * kit's in-place one (design-language §7): it opens on Cancel, Esc backs out, and focus returns to
 * the trigger. A refusal is read under the sentence, and the confirm stays open to retry or cancel.
 */
const props = defineProps<{ orgId: OrganizationId; account: ProviderAccount }>();
const emit = defineEmits<{ removed: [] }>();
const router = useRouter();
const confirming = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
const inUse = (details: unknown) => {
  const r = decoders.decode(
    decoders.object({ missions: decoders.array(decoders.object({ name: decoders.string }), 500) }),
    details,
  );
  return r.ok ? r.value.missions.map((m) => m.name) : null;
};

async function remove() {
  busy.value = true;
  failure.value = null;
  try {
    const r = await removeAccount(props.orgId, props.account.id);
    if (r.ok) {
      emit("removed");
      return void router.push({ name: "org.provider-accounts" });
    }
    const missions = "details" in r.error ? inUse(r.error.details) : null;
    failure.value = missions
      ? `Used by ${missions.join(", ")}. Unlink it from ${missions.length === 1 ? "that mission" : "them"} first.`
      : failureOutcome(r.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="mt-3 flex flex-col gap-2">
    <p v-if="account.missions.length > 0" class="m-0 text-sm text-text-3">
      Used by
      {{ account.missions.length === 1 ? "1 mission" : `${account.missions.length} missions` }}.
      Unlink it from {{ account.missions.length === 1 ? "that mission" : "them" }} before removing
      it.
    </p>
    <ApInlineConfirm
      v-else
      v-model:open="confirming"
      action="Remove account"
      :busy="busy"
      busy-reason="Removing…"
      :refusal="failure"
      @confirm="remove"
      @cancel="failure = null"
    >
      <template #trigger="{ attrs }">
        <ApButton variant="danger" size="compact" class="self-start" v-bind="attrs"
          >Remove account…</ApButton
        >
      </template>
      Remove {{ account.name }}? Missions can't book with it afterwards.
    </ApInlineConfirm>
  </div>
</template>
