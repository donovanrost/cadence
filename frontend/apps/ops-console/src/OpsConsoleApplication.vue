<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onBeforeUnmount, onMounted, provide, ref, shallowRef } from "vue";
import { OPS_COMPONENTS } from "./ops-components";
import { OPS_EVENT_BRIDGE, type OpsEventPayload } from "./ops-events";
import { unwrapOpsConsoleResponse, type OpsConsolePresentation } from "./ops-console";

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<OpsConsolePresentation>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionNotice = ref<string>();
let loadGeneration = 0;

const surfaceComponents = {
  workspace: OPS_COMPONENTS.OpsConsoleLanding,
  ops: OPS_COMPONENTS.OpsConsoleLanding,
} as const;
const actionListeners = computed(() =>
  Object.fromEntries(
    props.surface.actions.map((actionId) => [
      actionId,
      (input: unknown) => void executeAction(actionId, input),
    ]),
  ),
);

provide(OPS_EVENT_BRIDGE, props.bridge);

onMounted(() => {
  window.addEventListener("cadence:ops-event", onOpsEvent);
  void loadSurface();
});

onBeforeUnmount(() => {
  window.removeEventListener("cadence:ops-event", onOpsEvent);
});

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    if (!surfaceComponents[props.surface.surfaceId as "workspace" | "ops"]) {
      throw new Error("The selected Ops Console surface is unavailable.");
    }

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
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

async function onOpsEvent(event: Event): Promise<void> {
  if (!(event instanceof CustomEvent)) return;

  const detail = event.detail as { eventName?: string; payload?: OpsEventPayload };
  const actionId = detail.eventName;
  if (!actionId || actionPending.value) return;
  if (!props.surface.actions.includes(actionId)) {
    error.value = `Phoenix did not declare ${actionId} for ${props.surface.surfaceId}.`;
    return;
  }

  await executeAction(actionId, detail.payload);
}

async function executeAction(actionId: string, input: unknown): Promise<void> {
  if (actionPending.value) return;

  actionPending.value = true;
  actionNotice.value = undefined;
  error.value = undefined;

  try {
    await props.bridge.execute({
      applicationKey: props.application.applicationKey,
      applicationVersion: props.application.applicationVersion,
      actionId,
      input: isRecord(input) ? input : {},
      context: props.context,
    });
    actionNotice.value = `Phoenix accepted ${actionId}.`;
    await loadSurface();
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : "The Ops Console action failed.";
  } finally {
    actionPending.value = false;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <div
    id="ops-console-application"
    class="ops-console-application"
    :data-ops-console-surface="props.surface.surfaceId"
    data-ops-console-renderer="OpsConsoleLanding"
  >
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
        <CButton id="retry-ops-console" size="sm" @click="loadSurface">Retry query</CButton>
      </template>
    </CStatePanel>
    <template v-else-if="presentation">
      <aside v-if="actionPending" id="ops-console-action-loading" role="status" aria-live="polite">
        Sending the operation to Phoenix…
      </aside>
      <aside v-if="actionNotice" id="ops-console-action-notice" role="status" aria-live="polite">
        {{ actionNotice }}
      </aside>
      <component
        :is="OPS_COMPONENTS[presentation.component]"
        v-bind="presentation.props"
        v-on="actionListeners"
      />
    </template>
  </div>
</template>
