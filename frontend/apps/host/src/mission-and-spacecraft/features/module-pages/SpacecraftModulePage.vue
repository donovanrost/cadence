<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import type { SpacecraftPageContext } from "@cadence/plugin-sdk/spacecraft-pages";
import { spacecraftModulePages } from "./contributions";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: SpacecraftPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
}>();
const crashed = ref(false);
watch(
  () => [props.snapshot, props.context, props.contributionId],
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const admitted = computed(() => {
  if (!Object.hasOwn(spacecraftModulePages, props.contributionId)) return null;
  const registration = spacecraftModulePages[props.contributionId],
    snapshot = props.snapshot;
  if (
    !record(snapshot) ||
    snapshot.id !== registration.id ||
    snapshot.slot !== registration.slot ||
    snapshot.version !== registration.version ||
    snapshot.status !== "ready" ||
    !record(snapshot.context)
  )
    return null;
  for (const key of ["organizationId", "missionId", "spacecraftId"] as const) {
    if (
      typeof props.context[key] !== "string" ||
      !props.context[key] ||
      snapshot.context[key] !== props.context[key]
    )
      return null;
  }
  try {
    return {
      component: registration.component,
      props: registration.read(snapshot.data, props.context),
    };
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="spacecraft-module-page">
    <div
      v-if="crashed || !admitted"
      id="spacecraft-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This spacecraft feature is unavailable. The current Cadence page remains available.</p>
      <button
        id="spacecraft-module-retry"
        type="button"
        class="btn btn-sm mt-4"
        :disabled="refreshing"
        @click="refresh"
      >
        Retry
      </button>
    </div>
    <component v-else :is="admitted.component" v-bind="admitted.props" />
  </section>
</template>
