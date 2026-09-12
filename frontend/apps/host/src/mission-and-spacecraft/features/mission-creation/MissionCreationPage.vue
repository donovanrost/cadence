<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue";
import MissionNew from "./MissionNew.vue";
import { assertCreation } from "./validation";
import type { CreateMission, MissionInput } from "./contracts";
import { record, list, text } from "../../shared/validation";

const props = defineProps<{ data: Record<string, unknown>; execute: CreateMission }>();
const data = computed(() => {
  const value = props.data;
  assertCreation(value);
  return value;
});
const busy = ref(false);
const error = ref<string | null>(null);
const errors = ref<Record<string, string[]>>({});
let generation = 0;
let stopped = false;
onBeforeUnmount(() => {
  stopped = true;
  generation++;
});
async function act(event: "validate" | "save", input: MissionInput) {
  if (busy.value) return;
  const current = ++generation;
  if (event === "save") busy.value = true;
  error.value = null;
  try {
    const result = await props.execute(event, input);
    if (stopped || current !== generation) return;
    if (!record(result) || !["ok", "invalid", "unavailable"].includes(String(result.status)))
      throw new Error();
    if (result.status === "unavailable") throw new Error();
    if (
      !record(result.errors) ||
      !Object.entries(result.errors).every(
        ([key, value]) => ["display_name", "slug"].includes(key) && list(text)(value),
      )
    )
      throw new Error();
    errors.value = result.errors as Record<string, string[]>;
  } catch {
    if (!stopped && current === generation)
      error.value =
        "The mission request could not be completed. Check your connection and try again.";
  } finally {
    if (!stopped && current === generation) busy.value = false;
  }
}
</script>
<template>
  <div :aria-busy="busy">
    <p v-if="busy" id="mission-create-pending" role="status">Creating mission…</p>
    <p v-if="error" id="mission-create-error" role="alert">{{ error }}</p>
    <MissionNew
      v-bind="data"
      :errors="errors"
      :disabled="busy"
      @validate="act('validate', $event)"
      @save="act('save', $event)"
    />
  </div>
</template>
