<script setup lang="ts">
import {
  createFederatedActionLifecycle,
  type FullPageSurfaceProps,
  type HostActionReceipt,
} from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import ApplicationHost from "./ApplicationHost.vue";
import TelemetryDecomManage from "./TelemetryDecomManage.vue";

const props = defineProps<FullPageSurfaceProps>();

const surfaceComponents: Record<string, Component> = {
  manage: TelemetryDecomManage,
  packet_bindings: ApplicationHost,
};

const actionBindings: Record<string, Record<string, string>> = {
  manage: {
    change_revision: "save_configuration",
    save_catalog_revision: "save_configuration",
    enable: "request_activation",
    disable: "disable",
  },
  packet_bindings: { application_action: "save_packet_bindings" },
};

const pageProps = shallowRef<Record<string, unknown>>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionError = ref<string>();
const actionNotice = ref<string>();
const actionReceipt = shallowRef<HostActionReceipt<unknown>>();
let loadGeneration = 0;

const selectedComponent = computed(() => surfaceComponents[props.surface.surfaceId]);
const selectedBindings = computed(() => actionBindings[props.surface.surfaceId] ?? {});

const actionLifecycle = createFederatedActionLifecycle({
  applicationKey: props.application.applicationKey,
  applicationVersion: props.application.applicationVersion,
  surfaceId: props.surface.surfaceId,
  surfaceVersion: props.surface.version,
  declaredActions: props.surface.actions,
  context: props.context,
  execute: props.bridge.execute,
  requery: loadSurface,
  navigate: (href) => window.location.assign(href),
  onStarted: () => {
    actionPending.value = true;
    actionError.value = undefined;
    actionNotice.value = undefined;
    actionReceipt.value = undefined;
  },
  onCompleted: (actionId, receipt) => {
    actionReceipt.value = receipt;
    actionNotice.value = `Phoenix completed ${actionId}.`;
  },
  onRejected: (actionId, reason) => {
    actionError.value = reason instanceof Error ? reason.message : `The ${actionId} action failed.`;
  },
  onFinished: () => {
    actionPending.value = false;
  },
});

onBeforeUnmount(() => actionLifecycle.invalidate());
onMounted(() => void loadSurface());

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  pageProps.value = undefined;

  try {
    if (!selectedComponent.value)
      throw new Error("The selected telemetry surface has no renderer.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    pageProps.value = pagePropsFor(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The telemetry surface query failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

const listeners = computed(() =>
  Object.fromEntries(
    Object.entries(selectedBindings.value).map(([event, actionId]) => [
      event,
      (input: unknown) => void actionLifecycle.execute(actionId, actionInput(event, input) ?? {}),
    ]),
  ),
);

function actionInput(event: string, input: unknown): unknown {
  if (event === "application_action" && isRecord(input)) return input.application_action ?? {};
  if (isRecord(input) && "action-id" in input) {
    const { ["action-id"]: _actionId, ...rest } = input;
    return rest;
  }
  return input;
}

function pagePropsFor(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) return {};
  if (props.surface.surfaceId === "packet_bindings") return value;
  if (isRecord(value.trusted_surface)) {
    return isRecord(value.trusted_surface.data)
      ? value.trusted_surface.data
      : value.trusted_surface;
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <div id="telemetry-decom-application">
    <CStatePanel
      v-if="loading"
      id="telemetry-decom-loading"
      title="Loading telemetry surface"
      :description="
        actionPending
          ? 'Phoenix is processing the action and refreshing this surface.'
          : 'Requesting the Phoenix-owned presentation from the host.'
      "
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="telemetry-decom-error"
      title="Telemetry surface unavailable"
      :description="error"
      tone="error"
      aria-live="assertive"
    >
      <template #action>
        <CButton id="retry-telemetry-decom" size="sm" @click="loadSurface"> Retry query </CButton>
      </template>
    </CStatePanel>
    <div v-else-if="selectedComponent && pageProps" :data-surface-id="props.surface.surfaceId">
      <aside
        v-if="actionPending"
        id="telemetry-decom-action-loading"
        role="status"
        aria-live="polite"
      >
        Sending the telemetry action to Phoenix…
      </aside>
      <aside
        v-if="actionError"
        id="telemetry-decom-action-error"
        role="alert"
        aria-live="assertive"
      >
        {{ actionError }}
      </aside>
      <aside
        v-if="actionNotice && actionReceipt"
        id="telemetry-decom-action-notice"
        role="status"
        aria-live="polite"
        :data-receipt-id="actionReceipt.receiptId"
        :data-completed-at="actionReceipt.completedAt"
      >
        {{ actionNotice }} Receipt {{ actionReceipt.receiptId }} completed at
        {{ actionReceipt.completedAt }}.
      </aside>
      <component :is="selectedComponent" v-bind="pageProps" v-on="listeners" />
    </div>
  </div>
</template>
