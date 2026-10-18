<script setup lang="ts">
import { computed } from "vue";
import { useLazyPage } from "../../../shell/module-pages/lazy-pages";
import type { MissionPageContext, MissionPageAction } from "@cadence/plugin-sdk/mission-pages";
import { missionModulePages } from "./mission-contributions";
import { capturePage, createPageActionPort } from "../../../shell/module-pages/page-admission";
import { usePageBoundary } from "../../../shell/module-pages/use-page-boundary";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: MissionPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
  execute?: (request: MissionPageAction) => Promise<unknown>;
  navigate?: (href: string) => void;
}>();
const boundary = usePageBoundary(props, "mission.page");
const { crashed, retrying, diagnosticId } = boundary;
const loaded = useLazyPage(
  () => props.contributionId,
  missionModulePages,
  (cause) => boundary.report("load", cause),
);
const loading = computed(() => loaded.state.value.kind === "loading");
async function retry() {
  await boundary.retry();
  loaded.reload();
}
const admitted = computed(() => {
  try {
    const state = loaded.state.value;
    if (state.kind !== "ready") return null;
    const registration = state.value;
    const captured = capturePage(
      props,
      registration,
      ["organizationId", "missionId"],
      boundary.alive,
    );
    const featureProps = registration.read(captured.data, props.context);
    const port = registration.actions
      ? createPageActionPort(
          { ...registration, actions: registration.actions },
          captured.token,
          captured.current,
          props,
          "mission page",
        )
      : undefined;
    return {
      component: registration.component,
      key: typeof captured.token === "string" ? captured.token : registration.id,
      props: { ...featureProps, ...(port ? { port } : {}) },
    };
  } catch (cause) {
    boundary.report("admission", cause);
    return null;
  }
});
</script>
<template>
  <section id="mission-module-page">
    <div v-if="loading" id="mission-module-loading" role="status" class="p-6">Loading feature…</div>
    <div
      v-else-if="crashed || !admitted"
      id="mission-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This mission feature is unavailable. The current Cadence page remains available.</p>
      <p v-if="diagnosticId" class="mt-2 text-xs">Reference: {{ diagnosticId }}</p>
      <button
        id="mission-module-retry"
        type="button"
        class="btn btn-sm mt-4"
        :disabled="refreshing || retrying"
        @click="retry"
      >
        Retry
      </button>
    </div>
    <component v-else :is="admitted.component" :key="admitted.key" v-bind="admitted.props" />
  </section>
</template>
