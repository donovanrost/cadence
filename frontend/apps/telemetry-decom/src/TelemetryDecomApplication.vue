<script setup lang="ts">
import {
  createFederatedActionLifecycle,
  type FullPageSurfaceProps,
  type HostActionReceipt,
} from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import {
  packetBindingsContribution,
  type PacketPort,
} from "@cadence/telemetry-decom/packet-bindings";
const PacketBindingsSurface = packetBindingsContribution.component;
import { configurationContribution } from "@cadence/telemetry-decom/configuration";
const TelemetryDecomManage = configurationContribution.component;

const props = defineProps<FullPageSurfaceProps>();

const surfaceComponents: Record<string, Component> = {
  manage: TelemetryDecomManage,
  packet_bindings: PacketBindingsSurface,
};

const actionBindings: Record<string, Record<string, string>> = {
  manage: configurationContribution.actions,
  packet_bindings: {},
};

const packetPort: PacketPort = {
  read: async () =>
    pagePropsFor(
      await props.bridge.query({
        queryId: packetBindingsContribution.query.id,
        version: packetBindingsContribution.query.version,
        context: props.context,
      }),
    ),
  save: (input, idempotencyKey) =>
    props.bridge.execute({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      surfaceId: packetBindingsContribution.surfaceId,
      surfaceVersion: 1,
      actionId: packetBindingsContribution.actionId,
      input,
      idempotencyKey,
      context: props.context,
    }),
  navigate: (href) => (props.bridge.navigate ?? ((target) => window.location.assign(target)))(href),
};

const pageProps = shallowRef<Record<string, unknown>>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionError = ref<string>();
const actionNotice = ref<string>();
const actionReceipt = shallowRef<HostActionReceipt<unknown>>();
let loadGeneration = 0;

const selectedComponent = computed(() =>
  Object.hasOwn(surfaceComponents, props.surface.surfaceId)
    ? surfaceComponents[props.surface.surfaceId]
    : undefined,
);
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
  navigate: (href) => (props.bridge.navigate ?? ((target) => window.location.assign(target)))(href),
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
    <section
      v-if="loading"
      id="telemetry-decom-loading"
      class="card min-h-80 border border-base-300 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body flex items-center justify-center gap-5 p-8 text-base-content/70">
        <span
          class="loading loading-spinner loading-md"
          aria-label="Loading telemetry surface"
        ></span>
        <div>
          <strong class="mb-1 block text-lg font-medium tracking-tight text-base-content"
            >Loading telemetry surface</strong
          >
          <p class="text-sm leading-6">
            {{
              actionPending
                ? "Phoenix is processing the action and refreshing this surface."
                : "Requesting the Phoenix-owned presentation from the host."
            }}
          </p>
        </div>
      </div>
    </section>
    <section
      v-else-if="error"
      id="telemetry-decom-error"
      class="card border border-error/40 bg-base-200"
      aria-live="assertive"
    >
      <div class="card-body p-6">
        <div class="flex items-start gap-3">
          <span
            class="grid size-10 shrink-0 place-items-center border border-error font-mono text-error"
            aria-hidden="true"
            >!</span
          >
          <div>
            <strong class="block text-lg font-medium tracking-tight text-base-content"
              >Telemetry surface unavailable</strong
            >
            <p class="mt-1 text-sm leading-6 text-base-content/70">{{ error }}</p>
            <button
              id="retry-telemetry-decom"
              type="button"
              class="btn btn-sm mt-5"
              @click="loadSurface"
            >
              Retry query
            </button>
          </div>
        </div>
      </div>
    </section>
    <div v-else-if="selectedComponent && pageProps" :data-surface-id="props.surface.surfaceId">
      <aside
        v-if="actionPending"
        id="telemetry-decom-action-loading"
        role="status"
        aria-live="polite"
        class="mb-4 border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
      >
        Sending the telemetry action to Phoenix…
      </aside>
      <aside
        v-if="actionError"
        id="telemetry-decom-action-error"
        role="alert"
        aria-live="assertive"
        class="mb-4 border border-error/40 bg-error/10 px-4 py-3 text-sm text-error"
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
        class="mb-4 border border-success/40 bg-success/10 px-4 py-3 text-sm text-base-content"
      >
        {{ actionNotice }} Receipt {{ actionReceipt.receiptId }} completed at
        {{ actionReceipt.completedAt }}.
      </aside>
      <component
        :is="selectedComponent"
        v-bind="pageProps"
        :document="pageProps"
        :port="packetPort"
        v-on="listeners"
        :host-context="props.context"
        :busy="actionPending"
      />
    </div>
  </div>
</template>
