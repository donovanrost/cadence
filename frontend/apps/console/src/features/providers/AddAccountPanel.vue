<script setup lang="ts">
import { ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery, type SessionOrganization } from "@/api";
import {
  diffEdits,
  failureOutcome,
  SchemaForm,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApPanel, ApRemote, ApSelect } from "@/ui";
import CredentialFields from "./CredentialFields.vue";
import { createAccount, fetchAdapterSchema, fieldErrors } from "./api.ts";
import { INGESTION_PATH, type OfferedMode } from "./ingestion.ts";
import IngestionField from "./IngestionField.vue";

/** Add a provider account: adapter, name, adapter settings, credential reference. */
const props = defineProps<{
  organization: SessionOrganization;
  adapters: readonly Readonly<{ key: string; label: string }>[];
}>();
const emit = defineEmits<{ added: [id: string] }>();
const router = useRouter();
const adapter = ref(props.adapters[0]?.key ?? "");
const name = ref("");
const values = ref<FormValues>({});
const backend = ref("external");
const reference = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const schema = useRemoteQuery(
  () => (adapter.value ? { orgId: props.organization.id, adapter: adapter.value } : null),
  fetchAdapterSchema,
);
/** U77: booking updates get their own field (ux's words), not the generic schema row. */
const settingsOf = (fields: readonly SchemaField[]) =>
  fields.filter((f) => !f.path.startsWith("credential.") && f.path !== INGESTION_PATH);
const hasIngestion = (fields: readonly SchemaField[]) =>
  fields.some((f) => f.path === INGESTION_PATH);
const mode = ref<OfferedMode>("polling");
const providerName = () =>
  props.adapters.find((a) => a.key === adapter.value)?.label ?? "the provider";
watch(adapter, () => ((values.value = {}), (mode.value = "polling")));

async function save() {
  if (schema.state.value.status !== "ready" || busy.value) return;
  const fields = settingsOf(schema.state.value.value.fields);
  const edits = diffEdits({ kind: "provider_account", fields }, {}, values.value);
  const local: Record<string, string> = edits.ok ? {} : { ...edits.errors };
  if (!name.value.trim()) local.name = "Name the account.";
  if (!reference.value.trim()) local["credential.key"] = "Say where the secret lives.";
  errors.value = local;
  if (!edits.ok || Object.keys(local).length > 0) return;
  busy.value = true;
  failure.value = null;
  try {
    const r = await createAccount(props.organization.id, {
      provider_key: adapter.value,
      name: name.value.trim(),
      settings: {
        ...Object.fromEntries(edits.changes.map((c) => [c.path, c.value])),
        ...(hasIngestion(schema.state.value.value.fields) ? { [INGESTION_PATH]: mode.value } : {}),
      },
      credential: { backend: backend.value, key: reference.value.trim() },
    });
    if (r.ok) {
      emit("added", r.value.id);
      return void router.push({ name: "org.provider-accounts", params: { accountId: r.value.id } });
    }
    errors.value = "details" in r.error ? fieldErrors(r.error.details) : {};
    failure.value = failureOutcome(r.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="V2" title="Add provider account">
    <template #meta>
      <RouterLink :to="{ name: 'org.provider-accounts' }" class="text-text-3 hover:text-readout"
        >Cancel</RouterLink
      >
    </template>
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <ApSelect
          v-model="adapter"
          label="Provider"
          :options="adapters.map((a) => ({ value: a.key, label: a.label }))"
        />
        <ApField v-model="name" label="Account name" :error="errors.name ?? null" />
      </div>
      <ApRemote
        :state="schema.state.value"
        loading-label="Loading provider fields…"
        @retry="schema.refetch"
      >
        <template #default="{ value: s }">
          <SchemaForm
            v-model="values"
            :schema="{ kind: s.kind, fields: settingsOf(s.fields) }"
            :errors="errors"
          />
          <IngestionField
            v-if="hasIngestion(s.fields)"
            v-model="mode"
            :provider="providerName()"
            :from="null"
            :error="errors[INGESTION_PATH] ?? null"
          />
        </template>
      </ApRemote>
      <CredentialFields
        v-model:backend="backend"
        v-model:reference="reference"
        :org-slug="organization.slug"
        :errors="errors"
      />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <div class="flex items-center gap-3">
        <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="save"
          >Add account</ApButton
        >
        <span class="text-sm text-text-3">It saves as Not checked; test the reference next.</span>
      </div>
    </div>
  </ApPanel>
</template>
