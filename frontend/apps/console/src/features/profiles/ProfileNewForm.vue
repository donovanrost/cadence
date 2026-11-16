<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  diffEdits,
  FailureOutcomeCallout,
  failureOutcome,
  refreshConfigState,
  SchemaForm,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { ApButton, ApField, ApPanel } from "@/ui";
import { createOp, type NewProfileForm } from "./newProfile.ts";

/** Profile.md New profile: name + the generated fields, staged as one create in a change set. */
const props = defineProps<{
  missionId: MissionId;
  form: NewProfileForm;
  initialName: string;
  /** Duplicate: the source, so the form says what was copied (ux). */
  copiedFrom?: Readonly<{ name: string; version: number }> | undefined;
}>();
const router = useRouter();
const name = ref(props.initialName);
const values = ref({ ...props.form.values });
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<FailureOutcome | null>(null);
const busy = ref(false);
const blocked = computed(() => (name.value.trim() === "" ? "Name the profile first." : null));

async function stage() {
  if (blocked.value !== null || busy.value) return;
  // Every filled field goes into the new document (nothing exists to diff against).
  const edits = diffEdits(props.form.schema, {}, values.value);
  if (!edits.ok) return void (errors.value = edits.errors);
  errors.value = {};
  busy.value = true;
  failure.value = null;
  try {
    const r = await stageChange(props.missionId, {
      summary: `Add profile ${name.value.trim()}`,
      source: { surface: "profile_new" },
      ops: [createOp(name.value, props.form.carried, edits.changes)],
    });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged"));
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="N1" title="New profile">
    <form class="flex flex-col gap-4" @submit.prevent="stage">
      <!-- A create moves no spacecraft (spacecraft_profile write :create), so the last clause holds. -->
      <p v-if="copiedFrom" class="m-0 text-md text-text-3">
        Copied from {{ copiedFrom.name }} v{{ copiedFrom.version }}: its fields, routing rules and
        app settings. No spacecraft use it until you assign them.
      </p>
      <ApField v-model="name" label="Name" required />
      <SchemaForm v-model="values" :schema="form.schema" :errors="errors" />
      <FailureOutcomeCallout v-if="failure" :outcome="failure" tone="caution" />
      <div class="flex flex-wrap gap-2">
        <ApButton
          type="submit"
          variant="primary"
          :disabled="busy || blocked !== null"
          :disabled-reason="blocked ?? 'Staging…'"
          >Stage new profile</ApButton
        >
        <ApButton :to="{ name: 'setup.profiles' }">Cancel</ApButton>
      </div>
      <p class="m-0 text-sm text-text-3">Nothing is live until the change set is applied.</p>
    </form>
  </ApPanel>
</template>
