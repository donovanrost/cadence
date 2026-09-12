<script setup lang="ts">
import { computed } from "vue";
import { useLazyPage } from "../../../shell/module-pages/lazy-pages";
import type { SpacecraftPageContext } from "@cadence/plugin-sdk/spacecraft-pages";
import { spacecraftModulePages } from "./contributions";
import { capturePage } from "../../../shell/module-pages/page-admission";
import { usePageBoundary } from "../../../shell/module-pages/use-page-boundary";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: SpacecraftPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
}>();
const boundary = usePageBoundary(props, "spacecraft.page");
const { crashed, retrying, diagnosticId } = boundary;
const loaded = useLazyPage(
  () => props.contributionId,
  spacecraftModulePages,
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
      ["organizationId", "missionId", "spacecraftId"],
      boundary.alive,
    );
    const featureProps = registration.read(captured.data, props.context);
    return {
      component: registration.component,
      key: typeof captured.token === "string" ? captured.token : registration.id,
      props: { ...featureProps },
    };
  } catch (cause) {
    boundary.report("admission", cause);
    return null;
  }
});
</script>
<template>
  <section id="spacecraft-module-page">
    <div v-if="loading" id="spacecraft-module-loading" role="status" class="p-6">
      Loading feature…
    </div>
    <div
      v-else-if="crashed || !admitted"
      id="spacecraft-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This spacecraft feature is unavailable. The current Cadence page remains available.</p>
      <p v-if="diagnosticId" class="mt-2 text-xs">Reference: {{ diagnosticId }}</p>
      <button
        id="spacecraft-module-retry"
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
