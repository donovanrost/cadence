<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import { missionPages } from "./pages";
import { record } from "./shared/validation";
import MissionCreationPage from "./features/mission-creation/MissionCreationPage.vue";
import type { CreateMission } from "./features/mission-creation/contracts";
const props = defineProps<{
  page: string;
  snapshot: unknown;
  execute: CreateMission;
  refresh: () => Promise<void>;
}>();
const crashed = ref(false);
watch(
  () => props.snapshot,
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const snapshot = props.snapshot;
  if (
    !Object.hasOwn(missionPages, props.page) ||
    !record(snapshot) ||
    snapshot.page !== props.page ||
    snapshot.version !== 1 ||
    snapshot.status !== "ready" ||
    !record(snapshot.data)
  )
    return null;
  const registration = missionPages[props.page]!;
  try {
    registration.validate(snapshot.data);
    return { ...registration, data: snapshot.data };
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-mission-page">
    <div
      v-if="crashed || !admitted"
      id="core-mission-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This mission page is unavailable.</p>
      <button id="core-mission-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
    </div>
    <MissionCreationPage
      v-else-if="page === 'mission_new'"
      :data="admitted.data"
      :execute="execute"
    />
    <component :is="admitted.component" v-else v-bind="admitted.data" />
  </section>
</template>
