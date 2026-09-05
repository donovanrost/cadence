<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onMounted, ref, shallowRef } from "vue";
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
let loadGeneration = 0;

const selectedComponent = computed(() => surfaceComponents[props.surface.surfaceId]);
const selectedBindings = computed(() => actionBindings[props.surface.surfaceId] ?? {});

onMounted(loadSurface);

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  pageProps.value = undefined;

  try {
    if (!selectedComponent.value) throw new Error("The selected telemetry surface has no renderer.");

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

async function execute(actionId: string, input: unknown): Promise<void> {
  if (!props.surface.actions.includes(actionId)) {
    error.value = `Action ${actionId} is not declared by ${props.surface.surfaceId}.`;
    return;
  }

  loading.value = true;
  error.value = undefined;

  try {
    await props.bridge.execute({
      applicationKey: props.application.applicationKey,
      applicationVersion: props.application.applicationVersion,
      actionId,
      input: input ?? {},
      context: props.context,
    });
    await loadSurface();
  } catch (reason) {
    loading.value = false;
    error.value = reason instanceof Error ? reason.message : `The ${actionId} action failed.`;
  }
}

const listeners = computed(() =>
  Object.fromEntries(
    Object.entries(selectedBindings.value).map(([event, actionId]) => [
      event,
      (input: unknown) => execute(actionId, actionInput(event, input)),
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
    return isRecord(value.trusted_surface.data) ? value.trusted_surface.data : value.trusted_surface;
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
      description="Requesting the Phoenix-owned presentation from the host."
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
      <component :is="selectedComponent" v-bind="pageProps" v-on="listeners" />
    </div>
  </div>
</template>
