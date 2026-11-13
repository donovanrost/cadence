<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApField, ApSelect, ApSheet } from "@/ui";
import {
  fetchOrganization,
  fetchOrganizations,
  issueServiceIdentity,
  tokenFailure,
  type AdminServiceIdentities,
} from "./api.ts";
import TokenShown from "./TokenShown.vue";

/**
 * Issue a service identity (Admin.md): organization, name, what it may do in the server's words.
 * The token shows once; Done waits for "I've stored the token" and the sheet can't be dismissed
 * while it shows (ApSheet dismissible=false).
 */
const props = defineProps<{ capabilities: AdminServiceIdentities["capabilities"] }>();
const emit = defineEmits<{ issued: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const orgId = ref("");
const name = ref("");
const capability = ref("");
const missionId = ref("");
const token = ref<string | null>(null);
const stored = ref(false);
const failure = ref<string | null>(null);
const busy = ref(false);
const orgs = useRemoteQuery(() => ({ q: "", after: null }), fetchOrganizations);
const org = useRemoteQuery(() => (orgId.value ? orgId.value : null), fetchOrganization);
const orgOptions = computed(() =>
  orgs.state.value.status === "ready"
    ? orgs.state.value.value.organizations.map((o) => ({ value: o.id, label: o.name }))
    : [],
);
const capOptions = computed(() =>
  props.capabilities.flatMap((c) =>
    c.key === "unrecognized" ? [] : [{ value: c.key, label: c.label }],
  ),
);
const chosen = computed(() => props.capabilities.find((c) => c.key === capability.value) ?? null);
const missionOptions = computed(() =>
  org.state.value.status === "ready"
    ? org.state.value.value.missions.map((m) => ({ value: m.id, label: m.name }))
    : [],
);
const blocked = computed(() =>
  !orgId.value || !name.value.trim() || !chosen.value
    ? "Fill in the organization, name and what it may do."
    : chosen.value.needs_mission && !missionId.value
      ? "Choose the mission."
      : busy.value
        ? "Issuing…"
        : null,
);
function open() {
  orgId.value = name.value = capability.value = missionId.value = "";
  token.value = failure.value = null;
  stored.value = false;
  sheet.value?.open();
}
async function submit() {
  const c = chosen.value;
  if (blocked.value || !c || c.key === "unrecognized") return;
  busy.value = true;
  try {
    const r = await issueServiceIdentity({
      organization_id: orgId.value,
      name: name.value.trim(),
      capability: c.key,
      mission_id: c.needs_mission ? missionId.value : null,
    });
    if (!r.ok) {
      failure.value = tokenFailure(r.error, "issue");
      // A 2xx we couldn't read still issued it: refresh the list so it shows.
      if (r.error.kind === "malformed") emit("issued");
      return;
    }
    token.value = r.value.token;
    emit("issued");
  } finally {
    busy.value = false;
  }
}
function done() {
  token.value = null;
  sheet.value?.close();
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="token ? 'Store the token' : 'Issue a service identity'"
    :dismissible="!token"
  >
    <TokenShown v-if="token" v-model="stored" :token="token" />
    <form v-else class="flex flex-col gap-3" @submit.prevent="submit">
      <ApSelect v-model="orgId" label="Organization" :options="orgOptions" placeholder="Choose…" />
      <ApField v-model="name" label="Name" mono />
      <ApSelect
        v-model="capability"
        label="What it may do"
        :options="capOptions"
        placeholder="Choose…"
      />
      <ApSelect
        v-if="chosen?.needs_mission"
        v-model="missionId"
        label="Mission"
        :options="missionOptions"
        placeholder="Choose…"
      />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton
        v-if="token"
        variant="primary"
        :disabled="!stored"
        disabled-reason="Tick “I've stored the token” first."
        @click="done"
        >Done</ApButton
      >
      <template v-else>
        <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
        <ApButton
          variant="primary"
          :disabled="blocked !== null"
          :disabled-reason="blocked ?? undefined"
          @click="submit"
          >Issue</ApButton
        >
      </template>
    </template>
  </ApSheet>
</template>
