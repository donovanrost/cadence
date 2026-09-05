<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { onMounted, ref, shallowRef } from "vue";
import CommsOverviewPage from "./CommsOverviewPage.vue";
import {
  COMMS_OVERVIEW_QUERY_ID,
  COMMS_OVERVIEW_QUERY_VERSION,
  type CommsOverviewPresentation,
  unwrapCommsOverviewResponse,
} from "./comms-overview";

const props = defineProps<FederatedApplicationProps>();
const presentation = shallowRef<CommsOverviewPresentation>();
const loading = ref(true);
const error = ref<string>();
let loadGeneration = 0;

onMounted(loadOverview);

async function loadOverview(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    const response = await props.bridge.query<unknown>({
      queryId: COMMS_OVERVIEW_QUERY_ID,
      version: COMMS_OVERVIEW_QUERY_VERSION,
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
  <div id="comms-overview-application" class="comms-overview-application">
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
        <CButton id="retry-comms-overview" size="sm" @click="loadOverview"> Retry query </CButton>
      </template>
    </CStatePanel>
    <CommsOverviewPage v-else-if="presentation" :presentation="presentation" />
  </div>
</template>
