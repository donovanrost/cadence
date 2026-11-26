<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";
import GrantFields from "./GrantFields.vue";
import { issueFailure } from "./grant-refusals.ts";
import { issuedLine, sheetWords } from "./grant-words.ts";
import {
  blankGrant,
  generalError,
  grantBody,
  grantFailure,
  issueGrant,
  type GrantDraft,
  type Grants,
} from "./grants.ts";

/**
 * L3 Grant automation…: identity, three limits within the policy's ceilings, days, reason. U105:
 * its words follow the mission's approval setting (unread: the propose wording, never "at once").
 */
const props = defineProps<{ missionId: MissionId; grants: Grants }>();
const emit = defineEmits<{ granted: [said: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const draft = ref<GrantDraft>(blankGrant);
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const built = computed(() => grantBody(draft.value, props.grants.policy_version));
const chosen = computed(
  () => props.grants.service_identities.find((i) => i.id === draft.value.identity)?.name ?? null,
);
const words = computed(() => sheetWords(props.grants.approval_setting, chosen.value));

function open() {
  draft.value = blankGrant;
  errors.value = {};
  failure.value = null;
  sheet.value?.open();
}
async function submit() {
  const b = built.value;
  if (!b.ok || busy.value) return;
  busy.value = true;
  try {
    const r = await issueGrant(props.missionId, b.body);
    if (r.ok) {
      sheet.value?.close();
      return void emit("granted", issuedLine(r.value.grant));
    }
    errors.value = fieldErrors(r.error);
    failure.value =
      Object.keys(errors.value).length > 0
        ? generalError(errors.value)
        : (issueFailure(r.error, words.value.direct, chosen.value) ?? grantFailure(r.error));
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="words.title" initial-focus="select">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <GrantFields v-model="draft" :grants="grants" :errors="errors" />
      <ApTextarea
        :model-value="draft.reason"
        label="Reason"
        required
        :maxlength="2000"
        :error="errors['reason'] ?? null"
        @update:model-value="draft = { ...draft, reason: $event }"
      />
      <ApCallout v-if="failure" tone="crit" role="alert">{{ failure }}</ApCallout>
      <p class="m-0 text-sm text-text-3">{{ words.line }}</p>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!built.ok || busy"
        :disabled-reason="built.ok ? words.busy : built.why"
        @click="submit"
        >{{ words.commit }}</ApButton
      >
    </template>
  </ApSheet>
</template>
