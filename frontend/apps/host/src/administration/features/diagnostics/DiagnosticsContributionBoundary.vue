<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch, type Component } from "vue";
import {
  reportFrontendFailure,
  type FrontendFailureKind,
} from "../../../shell/frontend-diagnostics";
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
const diagnosticId = ref<string>();
const reported = new Set<FrontendFailureKind>();
function report(kind: FrontendFailureKind, cause: unknown) {
  if (reported.has(kind)) return;
  reported.add(kind);
  diagnosticId.value = reportFrontendFailure(
    {
      boundary: "administration.diagnostics",
      contributionId: props.contribution.id,
      version: props.contribution.version,
    },
    kind,
    cause,
  ).id;
}
watch(
  () => props.snapshots,
  () => {
    crashed.value = false;
    reported.clear();
    diagnosticId.value = undefined;
  },
);
onErrorCaptured((cause) => {
  crashed.value = true;
  report("render", cause);
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
  } catch (cause) {
    report("admission", cause);
    return null;
  }
});
</script>
<template>
  <section :id="`diagnostics-${contribution.id}`" :aria-label="contribution.title">
    <p v-if="crashed || !admitted" role="alert" class="border border-warning/40 bg-base-200 p-4">
      {{ contribution.title }} is unavailable. Refresh to try again.
      <span v-if="diagnosticId" class="block text-xs">Reference: {{ diagnosticId }}</span>
    </p>
    <component
      v-else
      :is="contribution.component"
      :data="admitted.data"
      :interactions="interactions"
    />
  </section>
</template>
