<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onMounted, ref, shallowRef } from "vue";
import CommsOverviewPage from "./CommsOverviewPage.vue";
import { unwrapCommsOverviewResponse, type CommsOverviewPresentation } from "./comms-overview";

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<CommsOverviewPresentation>();
const loading = ref(true);
const error = ref<string>();
let loadGeneration = 0;

const surfaceComponents = {
  overview: CommsOverviewPage,
} as const;
const renderer = computed(() => surfaceComponents[props.surface.surfaceId as "overview"]);

onMounted(() => void loadSurface());

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    if (!renderer.value) throw new Error("The selected communications surface is unavailable.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    presentation.value = unwrapCommsOverviewResponse(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The communications overview failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}
</script>

<template>
  <div
    id="comms-overview-application"
    class="comms-overview-application"
    :data-comms-overview-surface="props.surface.surfaceId"
    data-comms-overview-renderer="CommsOverviewPage"
  >
    <CStatePanel
      v-if="loading"
      id="comms-overview-loading"
      title="Loading communications overview"
      description="Requesting the mission-scoped presentation from the Phoenix host."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="comms-overview-error"
      title="Communications overview unavailable"
      :description="error"
      tone="error"
      aria-live="polite"
    >
      <template #action>
        <CButton id="retry-comms-overview" size="sm" @click="loadSurface">Retry query</CButton>
      </template>
    </CStatePanel>
    <component v-else-if="renderer && presentation" :is="renderer" :presentation="presentation" />
  </div>
</template>
