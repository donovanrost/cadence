<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { isKnown } from "@/api";
import { ApButton, ApCallout, ApField } from "@/ui";
import CredentialFields from "./CredentialFields.vue";
import { fieldErrors, updateAccount, type ProviderAccount } from "./api.ts";
import {
  INGESTION_LABEL,
  INGESTION_PATH,
  ingestionSaveLabel,
  ingestionWord,
  isOffered,
  type OfferedMode,
} from "./ingestion.ts";
import IngestionField from "./IngestionField.vue";

/**
 * Rename (no version), point at a new credential reference, and/or change booking updates (U77):
 * either of the last two saves a new version. Other settings wait for an account detail read.
 */
const props = defineProps<{ orgId: OrganizationId; orgSlug: string; account: ProviderAccount }>();
const emit = defineEmits<{ saved: [text: string]; cancel: [] }>();
const name = ref(props.account.name);
/** U77: the current mode as read; a webhook/hybrid account set up outside the console reads only. */
const current = props.account.event_ingestion_mode;
const currentKnown = current != null && isKnown(current) ? current : null;
const editableMode: OfferedMode | null =
  currentKnown !== null && isOffered(currentKnown) ? currentKnown : null;
const mode = ref<OfferedMode | null>(editableMode);
const provider = props.account.provider.label;
const backend = ref("external");
const reference = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const busy = ref(false);

async function save() {
  const renamed = name.value.trim() !== props.account.name;
  const replaced = reference.value.trim() !== "";
  const remoded = mode.value !== null && mode.value !== editableMode;
  if (!renamed && !replaced && !remoded) return void (failure.value = "Nothing changed yet.");
  if (!name.value.trim()) return void (errors.value = { name: "Name the account." });
  busy.value = true;
  failure.value = null;
  try {
    const r = await updateAccount(props.orgId, props.account.id, {
      ...(renamed ? { name: name.value.trim() } : {}),
      ...(replaced ? { credential: { backend: backend.value, key: reference.value.trim() } } : {}),
      ...(remoded && mode.value ? { settings: { [INGESTION_PATH]: mode.value } } : {}),
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
    <IngestionField
      v-if="mode !== null"
      v-model="mode"
      :provider="provider"
      :from="editableMode"
      :error="errors[INGESTION_PATH] ?? null"
    />
    <p v-else-if="currentKnown !== null" class="m-0 text-sm text-text-2">
      {{ INGESTION_LABEL }}: {{ ingestionWord(currentKnown, provider) }}. Set up outside the
      console; change it where it was set up.
    </p>
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
      <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="save">{{
        ingestionSaveLabel(mode, editableMode)
      }}</ApButton>
      <ApButton variant="ghost" @click="emit('cancel')">Cancel</ApButton>
    </div>
  </div>
</template>
