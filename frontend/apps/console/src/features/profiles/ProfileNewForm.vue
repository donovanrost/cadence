<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  diffEdits,
  failureOutcome,
  refreshConfigState,
  SchemaForm,
  stageChange,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApPanel } from "@/ui";
import { createOp, type NewProfileForm } from "./newProfile.ts";

/** Profile.md New profile: name + the generated fields, staged as one create in a change set. */
const props = defineProps<{ missionId: string; form: NewProfileForm; initialName: string }>();
const router = useRouter();
const name = ref(props.initialName);
const values = ref({ ...props.form.values });
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
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
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged").sentence);
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
      <ApField v-model="name" label="Name" required />
      <SchemaForm v-model="values" :schema="form.schema" :errors="errors" />
      <ApCallout v-if="failure" tone="caution">{{ failure }}</ApCallout>
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
