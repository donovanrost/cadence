<script setup lang="ts">
import { computed, ref } from "vue";
import { fieldErrors, type SessionOrganization } from "@/api";
import { ApButton, ApCallout, ApField, ApSelect, ApSheet, ApTextarea } from "@/ui";
import { accountFailure, grantToMission, type AccountDetail } from "./grants.ts";

/** L13 Grant to a mission: which mission, optionally narrower stations and a quota, and why. */
const props = defineProps<{ organization: SessionOrganization; detail: AccountDetail }>();
const emit = defineEmits<{ granted: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const mission = ref("");
const stations = ref("");
const quota = ref("");
const reason = ref("");
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const granted = computed(
  () => new Set(props.detail.grants.filter((g) => g.state === "active").map((g) => g.mission.id)),
);
const missions = computed(() =>
  props.organization.missions
    .filter((m) => !granted.value.has(m.id))
    .map((m) => ({ value: m.id, label: m.name })),
);
const quotaValue = computed(() => (/^\d+$/.test(quota.value.trim()) ? Number(quota.value) : null));
const blocked = computed(() =>
  !mission.value
    ? "Choose a mission."
    : quota.value.trim() && quotaValue.value === null
      ? "Quota is a whole number."
      : busy.value
        ? "Granting…"
        : null,
);
function open() {
  mission.value = stations.value = quota.value = reason.value = "";
  errors.value = {};
  failure.value = null;
  sheet.value?.open();
}
async function submit() {
  if (blocked.value !== null) return;
  busy.value = true;
  try {
    const list = stations.value
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const r = await grantToMission(
      { orgId: props.organization.id, accountId: props.detail.account.id },
      {
        mission_id: mission.value,
        expected_account_version: props.detail.account.version,
        ...(list.length > 0 ? { allowed_stations: list } : {}),
        ...(quotaValue.value !== null ? { max_quota: quotaValue.value } : {}),
        ...(reason.value.trim() ? { reason: reason.value.trim() } : {}),
      },
    );
    if (r.ok) {
      sheet.value?.close();
      return void emit("granted");
    }
    errors.value = fieldErrors(r.error);
    failure.value = Object.keys(errors.value).length > 0 ? null : accountFailure(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Grant to a mission" initial-focus="select">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <ApSelect
        v-model="mission"
        label="Mission"
        required
        :options="missions"
        placeholder="Choose…"
        :error="errors['mission_id'] ?? null"
      />
      <ApField
        v-model="stations"
        label="Only these stations"
        mono
        :hint="
          detail.account.guardrails.allowed_stations
            ? `Optional, comma-separated; within the account's ${detail.account.guardrails.allowed_stations.join(', ')}.`
            : 'Optional, comma-separated station refs.'
        "
        :error="errors['allowed_stations'] ?? null"
      />
      <ApField
        v-model="quota"
        label="Quota"
        inputmode="numeric"
        :error="
          errors['max_quota'] ??
          (quota.trim() && quotaValue === null ? 'Quota is a whole number.' : null)
        "
      />
      <ApTextarea v-model="reason" label="Why (optional)" :maxlength="2000" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >Grant</ApButton
      >
    </template>
  </ApSheet>
</template>
