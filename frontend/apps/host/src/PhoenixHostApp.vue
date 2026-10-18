<script setup lang="ts">
import { definedProperties } from "./defined-properties";
import type {
  CatalogApplication,
  FrontendApplicationCatalog,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import FederatedPageFrame from "./FederatedPageFrame.vue";
import RemoteApplicationBoundary from "./RemoteApplicationBoundary.vue";
import {
  loadPhoenixApplicationCatalog,
  selectPhoenixApplication,
  type PhoenixHostConfig,
} from "./phoenix-catalog-client";
import {
  createHttpHostBridge,
  isHostSessionFailure,
  type HostBridgeError,
} from "./http-host-bridge";

const DEFAULT_CATALOG_TIMEOUT_MS = 10_000;

type HostFailure = {
  message: string;
  referenceId: string;
};

const props = defineProps<
  PhoenixHostConfig & {
    navigate?: (href: string) => void;
    fetcher?: typeof globalThis.fetch;
    catalogTimeoutMs?: number;
  }
>();

const catalog = shallowRef<FrontendApplicationCatalog>();
const application = shallowRef<CatalogApplication>();
const bridge = shallowRef<HostBridge>();
const context = shallowRef<HostContext>();
const bootError = shallowRef<HostFailure>();
const actionFailure = shallowRef<HostFailure>();
const loading = ref(true);
const mountGeneration = ref(0);
let loadGeneration = 0;
let authRecoveryUsed = false;
let catalogAbortController: AbortController | undefined;
let activeBridgeInvalidator: (() => void) | undefined;

onMounted(loadCatalog);
onBeforeUnmount(() => {
  loadGeneration += 1;
  catalogAbortController?.abort(new Error("Phoenix host unmounted."));
  invalidateActiveContext();
});

async function loadCatalog({ automaticRecovery = false } = {}): Promise<void> {
  const generation = ++loadGeneration;
  catalogAbortController?.abort(
    new Error("A newer Phoenix host catalog load superseded this load."),
  );
  invalidateActiveContext();
  const controller = new AbortController();
  catalogAbortController = controller;
  loading.value = true;
  bootError.value = undefined;
  if (!automaticRecovery) actionFailure.value = undefined;
  catalog.value = undefined;
  application.value = undefined;
  bridge.value = undefined;
  context.value = undefined;

  try {
    const fetcher = props.fetcher ?? globalThis.fetch;
    if (typeof fetcher !== "function") {
      throw new Error("The Phoenix application host cannot fetch its catalog.");
    }

    const nextCatalog = await loadPhoenixApplicationCatalog(definedProperties(props), {
      fetch: (input, init) =>
        boundedCatalogFetch(
          fetcher,
          input,
          init,
          controller,
          props.catalogTimeoutMs ?? DEFAULT_CATALOG_TIMEOUT_MS,
        ),
    });
    const nextApplication = selectPhoenixApplication(nextCatalog, definedProperties(props));
    if (generation !== loadGeneration || controller.signal.aborted) return;

    catalog.value = nextCatalog;
    application.value = nextApplication;
    context.value = nextCatalog.session.context;
    const nextBridge = createHttpHostBridge(nextCatalog.session, nextApplication, {
      ...definedProperties({ queryParams: props.queryParams, navigate: props.navigate }),
      onSessionFailure: handleBridgeSessionFailure,
    });
    if (generation !== loadGeneration || controller.signal.aborted) {
      nextBridge.invalidate();
      return;
    }
    bridge.value = nextBridge;
    activeBridgeInvalidator = nextBridge.invalidate;
    mountGeneration.value += 1;
  } catch (reason) {
    if (generation !== loadGeneration) return;
    if (!automaticRecovery && !authRecoveryUsed && isHostSessionFailure(reason)) {
      authRecoveryUsed = true;
      await loadCatalog({ automaticRecovery: true });
      return;
    }
    bootError.value = catalogFailureFor(reason);
  } finally {
    if (generation === loadGeneration) loading.value = false;
    if (catalogAbortController === controller) catalogAbortController = undefined;
  }
}

function remountApplication(): void {
  mountGeneration.value += 1;
}

function handleBridgeSessionFailure(operation: "query" | "action", error: HostBridgeError): void {
  if (operation === "action") {
    actionFailure.value = {
      message: "The action was stopped. No automatic retry was attempted.",
      referenceId: error.referenceId,
    };
  }

  invalidateActiveContext();
  if (authRecoveryUsed) return;
  authRecoveryUsed = true;
  void loadCatalog({ automaticRecovery: true });
}

function invalidateActiveContext(): void {
  activeBridgeInvalidator?.();
  activeBridgeInvalidator = undefined;
}

function catalogFailureFor(reason: unknown): HostFailure {
  const detail = reason instanceof Error ? reason.message : "";
  const message = detail.startsWith("The application catalog does not provide")
    ? detail
    : "The authenticated application catalog could not be loaded.";
  return { message, referenceId: crypto.randomUUID() };
}

function boundedCatalogFetch(
  fetcher: typeof globalThis.fetch,
  input: RequestInfo | URL,
  init: RequestInit | undefined,
  controller: AbortController,
  timeoutMs: number,
): Promise<Response> {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return Promise.reject(new Error("The Phoenix catalog timeout must be positive."));
  }

  return new Promise<Response>((resolve, reject) => {
    let settled = false;
    const finishResponse = (response: Response): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      controller.signal.removeEventListener("abort", onAbort);
      resolve(response);
    };
    const finishError = (reason: unknown): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      controller.signal.removeEventListener("abort", onAbort);
      reject(reason);
    };
    const onAbort = () =>
      finishError(controller.signal.reason ?? new Error("Phoenix catalog load cancelled."));
    const timer = setTimeout(() => {
      const error = new Error("Phoenix catalog load timed out.");
      controller.abort(error);
      finishError(error);
    }, timeoutMs);

    controller.signal.addEventListener("abort", onAbort, { once: true });
    Promise.resolve()
      .then(() => fetcher(input, { ...init, signal: controller.signal }))
      .then(finishResponse, finishError);
  });
}
</script>

<template>
  <div id="cadence-phoenix-host" class="contents">
    <aside
      v-if="actionFailure"
      id="phoenix-host-action-stopped"
      class="alert alert-warning m-6 flex flex-col items-start gap-1"
      role="alert"
      aria-live="assertive"
    >
      <strong>Action stopped</strong>
      <span>{{ actionFailure.message }}</span>
      <span class="font-mono text-xs">Reference ID: {{ actionFailure.referenceId }}</span>
    </aside>

    <section
      v-if="loading"
      id="phoenix-host-loading"
      class="flex min-h-48 items-center justify-center gap-3 p-6"
      role="status"
      aria-live="polite"
    >
      <span class="loading loading-spinner loading-md" aria-hidden="true"></span>
      <span>Loading the approved application surface…</span>
    </section>

    <section v-else-if="bootError" id="phoenix-host-error" class="m-6 max-w-3xl" role="alert">
      <div class="alert alert-error flex flex-col items-start gap-3">
        <h2 class="text-lg font-semibold">The application catalog could not be loaded.</h2>
        <p>{{ bootError.message }}</p>
        <p id="phoenix-host-error-reference" class="font-mono text-xs">
          Reference ID: {{ bootError.referenceId }}
        </p>
        <button
          id="retry-phoenix-host"
          type="button"
          class="btn btn-primary btn-sm"
          @click="loadCatalog()"
        >
          Retry catalog
        </button>
      </div>
    </section>

    <FederatedPageFrame
      v-else-if="application && bridge && context"
      :application="application"
      :context="context"
    >
      <RemoteApplicationBoundary
        :key="`${application.release.releaseId}:${mountGeneration}`"
        :application="application"
        :bridge="bridge"
        :context="context"
        :fallback-href="props.fallbackHref"
        @retry="remountApplication"
      />
    </FederatedPageFrame>
  </div>
</template>
