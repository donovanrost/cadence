<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";
import { assertProfileForm, assertProfileResult } from "./validation";
import type { ProfileAction, ProfileData, ProfileErrors, ProfilePayload } from "./contracts";
const props = defineProps<{ data: Record<string, unknown>; execute: ProfileAction }>();
assertProfileForm(props.data);
const data = props.data as ProfileData;
const busy = ref(false);
const errors = ref<ProfileErrors>({});
const failure = ref(false);
let generation = 0;
let stopped = false;
onBeforeUnmount(() => {
  stopped = true;
  generation++;
});
async function act(event: "validate" | "save", input: ProfilePayload) {
  if (busy.value) return;
  const current = ++generation;
  if (event === "save") busy.value = true;
  failure.value = false;
  try {
    const result = await props.execute(event, input);
    if (stopped || current !== generation) return;
    assertProfileResult(result);
    errors.value = result.errors;
  } catch {
    if (!stopped && current === generation) failure.value = true;
  } finally {
    if (!stopped && current === generation) busy.value = false;
  }
}
</script>
<template>
  <div :aria-busy="busy">
    <p v-if="busy" id="profile-creation-pending" role="status">Saving profile…</p>
    <p v-if="failure" id="profile-creation-error" role="alert">
      The profile request could not be completed. Check your connection and try again.
    </p>
    <SpacecraftTypeNew
      v-bind="data"
      :errors="errors"
      :disabled="busy"
      @validate="act('validate', $event)"
      @save="act('save', $event)"
    />
  </div>
</template>
