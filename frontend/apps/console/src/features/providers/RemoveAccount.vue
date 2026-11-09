<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { decoders } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout } from "@/ui";
import { removeAccount, type ProviderAccount } from "./api.ts";

/** Remove (archive) an account; blocked with the reason while missions use it. */
const props = defineProps<{ orgId: string; account: ProviderAccount }>();
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
    confirming.value = false;
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
    <div v-else class="flex flex-wrap items-center gap-2">
      <ApButton v-if="!confirming" variant="danger" size="compact" @click="confirming = true"
        >Remove account</ApButton
      >
      <template v-else>
        <span class="text-sm text-text-2"
          >Remove {{ account.name }}? Missions can't book with it afterwards.</span
        >
        <ApButton
          variant="danger"
          size="compact"
          :disabled="busy"
          disabled-reason="Removing…"
          @click="remove"
          >Remove</ApButton
        >
        <ApButton variant="ghost" size="compact" @click="confirming = false">Keep</ApButton>
      </template>
    </div>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
  </div>
</template>
