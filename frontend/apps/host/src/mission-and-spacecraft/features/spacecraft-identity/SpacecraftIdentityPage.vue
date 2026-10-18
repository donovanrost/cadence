<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import SpacecraftIdentityForm from "./SpacecraftIdentityForm.vue";
import { assertIdentityForm, assertIdentityResult } from "./validation";
import type { IdentityAction, IdentityData, IdentityErrors, SpacecraftPayload } from "./contracts";
const props = defineProps<{ data: Record<string, unknown>; execute: IdentityAction }>();
assertIdentityForm(props.data);
const data = props.data as IdentityData;
const busy = ref(false);
const errors = ref<IdentityErrors>({});
const failure = ref(false);
let generation = 0;
let stopped = false;
onBeforeUnmount(() => {
  stopped = true;
  generation++;
});
async function act(event: "validate" | "save", input: SpacecraftPayload) {
  if (busy.value) return;
  const current = ++generation;
  if (event === "save") busy.value = true;
  failure.value = false;
  try {
    const result = await props.execute(event, input);
    if (stopped || current !== generation) return;
    assertIdentityResult(result);
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
    <p v-if="busy" id="spacecraft-identity-pending" role="status">Saving spacecraft…</p>
    <p v-if="failure" id="spacecraft-identity-error" role="alert">
      The spacecraft request could not be completed. Check your connection and try again.
    </p>
    <SpacecraftIdentityForm
      v-bind="data"
      :errors="errors"
      :disabled="busy"
      @validate="act('validate', $event)"
      @save="act('save', $event)"
    />
  </div>
</template>
