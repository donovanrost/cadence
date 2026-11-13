<script setup lang="ts">
import { computed, ref } from "vue";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import GrantFields from "./GrantFields.vue";
import {
  blankGrant,
  grantBody,
  grantFailure,
  issueGrant,
  type GrantDraft,
  type Grants,
} from "./grants.ts";

/** L3 Grant automation…: identity, three limits within the policy's ceilings, days, reason. */
const props = defineProps<{ missionId: string; grants: Grants }>();
const emit = defineEmits<{ granted: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const draft = ref<GrantDraft>(blankGrant);
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const built = computed(() => grantBody(draft.value, props.grants.policy_version));

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
      return void emit("granted");
    }
    errors.value = fieldErrors(r.error);
    failure.value = Object.keys(errors.value).length > 0 ? null : grantFailure(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Grant automation" initial-focus="select">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <GrantFields v-model="draft" :grants="grants" :errors="errors" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!built.ok || busy"
        :disabled-reason="built.ok ? 'Granting…' : built.why"
        @click="submit"
        >Grant</ApButton
      >
    </template>
  </ApSheet>
</template>
