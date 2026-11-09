<script setup lang="ts">
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField } from "@/ui";
import CredentialFields from "./CredentialFields.vue";
import { fieldErrors, updateAccount, type ProviderAccount } from "./api.ts";

/**
 * Rename (no version) and/or point at a new credential reference (a new version). Settings edits
 * wait for an account detail read to prefill from.
 */
const props = defineProps<{ orgId: string; orgSlug: string; account: ProviderAccount }>();
const emit = defineEmits<{ saved: [text: string]; cancel: [] }>();
const name = ref(props.account.name);
const backend = ref("external");
const reference = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const busy = ref(false);

async function save() {
  const renamed = name.value.trim() !== props.account.name;
  const replaced = reference.value.trim() !== "";
  if (!renamed && !replaced) return void (failure.value = "Nothing changed yet.");
  if (!name.value.trim()) return void (errors.value = { name: "Name the account." });
  busy.value = true;
  failure.value = null;
  try {
    const r = await updateAccount(props.orgId, props.account.id, {
      ...(renamed ? { name: name.value.trim() } : {}),
      ...(replaced ? { credential: { backend: backend.value, key: reference.value.trim() } } : {}),
    });
    if (r.ok)
      return void emit(
        "saved",
        r.value.version === null
          ? "Renamed."
          : `Saved as v${r.value.version}. Test the new reference next.`,
      );
    errors.value = "details" in r.error ? fieldErrors(r.error.details) : {};
    failure.value = failureOutcome(r.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-4 border-t border-hairline pt-4">
    <ApField v-model="name" label="Account name" :error="errors.name ?? null" />
    <div class="flex flex-col gap-1">
      <span class="ap-label">New credential reference</span>
      <span class="text-sm text-text-3"
        >Leave the reference blank to keep the current one. A new reference saves a new
        version.</span
      >
    </div>
    <CredentialFields
      v-model:backend="backend"
      v-model:reference="reference"
      :org-slug="orgSlug"
      :errors="errors"
    />
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <div class="flex gap-2">
      <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="save"
        >Save</ApButton
      >
      <ApButton variant="ghost" @click="emit('cancel')">Cancel</ApButton>
    </div>
  </div>
</template>
