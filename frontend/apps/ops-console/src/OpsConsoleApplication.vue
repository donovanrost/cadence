<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { onBeforeUnmount, onMounted, provide, ref, shallowRef } from "vue";
import { OPS_COMPONENTS } from "./ops-components";
import {
  OPS_EVENT_BRIDGE,
  type OpsEventPayload,
} from "./ops-events";
import {
  OPS_QUERY_ID,
  OPS_QUERY_VERSION,
  type OpsConsolePresentation,
  unwrapOpsConsoleResponse,
} from "./ops-console";

const props = defineProps<FederatedApplicationProps>();
const presentation = shallowRef<OpsConsolePresentation>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionNotice = ref<string>();
let loadGeneration = 0;

provide(OPS_EVENT_BRIDGE, props.bridge);

onMounted(() => {
  window.addEventListener("cadence:ops-event", onOpsEvent as EventListener);
  void loadConsole();
});

onBeforeUnmount(() => {
  window.removeEventListener("cadence:ops-event", onOpsEvent as EventListener);
});

async function loadConsole(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    const response = await props.bridge.query<unknown>({
      queryId: OPS_QUERY_ID,
      version: OPS_QUERY_VERSION,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    presentation.value = unwrapOpsConsoleResponse(response, OPS_COMPONENTS);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The Ops Console query failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function onOpsEvent(event: CustomEvent<{eventName: string; payload: OpsEventPayload}>): Promise<void> {
  const eventName = event.detail?.eventName;
  if (!eventName || actionPending.value) return;

  actionPending.value = true;
  actionNotice.value = undefined;

  try {
    await props.bridge.execute({
      applicationKey: "ops_console",
      applicationVersion: 1,
      actionId: eventName,
      input: event.detail.payload,
      context: props.context,
    });
    actionNotice.value = `Phoenix accepted ${eventName}.`;
    await loadConsole();
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : "The Ops Console action failed.";
  } finally {
    actionPending.value = false;
  }
}

function retry(): void {
  void loadConsole();
}
</script>

<template>
  <div id="ops-console-application" class="ops-console-application">
    <CStatePanel
      v-if="loading"
      id="ops-console-loading"
      title="Loading Ops Console"
      description="Requesting the mission-scoped operations presentation from Phoenix."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="ops-console-error"
      title="Ops Console unavailable"
      :description="error"
      tone="error"
      aria-live="polite"
    >
      <template #action>
        <CButton id="retry-ops-console" size="sm" @click="retry">Retry query</CButton>
      </template>
    </CStatePanel>
    <template v-else-if="presentation">
      <aside v-if="actionPending" id="ops-console-action-loading" role="status" aria-live="polite">
        Sending the operation to Phoenix…
      </aside>
      <aside v-if="actionNotice" id="ops-console-action-notice" role="status" aria-live="polite">
        {{ actionNotice }}
      </aside>
      <component :is="OPS_COMPONENTS[presentation.component]" v-bind="presentation.props" />
    </template>
  </div>
</template>
