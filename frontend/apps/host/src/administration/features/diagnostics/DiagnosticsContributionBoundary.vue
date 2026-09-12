<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch, type Component } from "vue";
import type {
  DiagnosticsContribution,
  DiagnosticsPanelInteractions,
  DiagnosticsSnapshot,
} from "@cadence/plugin-sdk";

const props = defineProps<{
  contribution: DiagnosticsContribution<Component>;
  snapshots: readonly DiagnosticsSnapshot[];
  interactions: DiagnosticsPanelInteractions;
}>();
const crashed = ref(false);
watch(
  () => props.snapshots,
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const matches = (Array.isArray(props.snapshots) ? props.snapshots : []).filter(
    (item) => item && item.id === props.contribution.id,
  );
  const snapshot = matches[0];
  if (
    matches.length !== 1 ||
    snapshot?.version !== props.contribution.version ||
    snapshot.status !== "ready"
  )
    return null;
  try {
    props.contribution.validate(snapshot.data);
    return snapshot;
  } catch {
    return null;
  }
});
</script>
<template>
  <section :id="`diagnostics-${contribution.id}`" :aria-label="contribution.title">
    <p v-if="crashed || !admitted" role="alert" class="border border-warning/40 bg-base-200 p-4">
      {{ contribution.title }} is unavailable. Refresh to try again.
    </p>
    <component
      v-else
      :is="contribution.component"
      :data="admitted.data"
      :interactions="interactions"
    />
  </section>
</template>
