<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  FrontendApplicationCatalog,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { CButton, CStatus } from "@cadence/ui";
import { onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
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

const props = withDefaults(
  defineProps<
    PhoenixHostConfig & {
      fetcher?: typeof globalThis.fetch;
      catalogTimeoutMs?: number;
    }
  >(),
  { fetcher: undefined, catalogTimeoutMs: undefined },
);

const catalog = shallowRef<FrontendApplicationCatalog>();
const application = shallowRef<CatalogApplication>();
const bridge = shallowRef<HostBridge>();
const context = shallowRef<HostContext>();
const manifest = shallowRef<FirstPartyApplicationManifest>();
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
  manifest.value = undefined;
  catalog.value = undefined;
  application.value = undefined;
  bridge.value = undefined;
  context.value = undefined;

  try {
    const fetcher = props.fetcher ?? globalThis.fetch;
    if (typeof fetcher !== "function") {
      throw new Error("The Phoenix application host cannot fetch its catalog.");
    }

    const nextCatalog = await loadPhoenixApplicationCatalog(props, {
      fetch: (input, init) =>
        boundedCatalogFetch(
          fetcher,
          input,
          init,
          controller,
          props.catalogTimeoutMs ?? DEFAULT_CATALOG_TIMEOUT_MS,
        ),
    });
    const nextApplication = selectPhoenixApplication(nextCatalog, props);
    if (generation !== loadGeneration || controller.signal.aborted) return;

    catalog.value = nextCatalog;
    application.value = nextApplication;
    context.value = nextCatalog.session.context;
    const nextBridge = createHttpHostBridge(nextCatalog.session, nextApplication, {
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
  manifest.value = undefined;
  mountGeneration.value += 1;
}

function recordManifest(value: FirstPartyApplicationManifest): void {
  manifest.value = value;
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

function contextLabel(): string {
  return context.value ? `${context.value.scope.toUpperCase()} CONTEXT` : "CONTEXT";
}

function contextName(): string {
  if (!context.value) return "RESOLVING";
  return context.value.scope === "spacecraft"
    ? context.value.spacecraftName
    : context.value.missionName;
}

function contextDetails(): string {
  if (!context.value) return "RESOLVING";
  if (context.value.scope === "spacecraft") {
    return `${context.value.missionId} · ${context.value.spacecraftId}`;
  }
  return context.value.missionId;
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
  <div id="cadence-phoenix-host" class="phoenix-host-shell">
    <header class="phoenix-host-header">
      <a id="phoenix-host-home" class="phoenix-host-wordmark" :href="props.fallbackHref">
        <span class="phoenix-host-signal" aria-hidden="true"><i></i><i></i><i></i></span>
        <span>CADENCE</span>
      </a>
      <div class="phoenix-host-context">
        <span>{{ contextLabel() }}</span>
        <strong>{{ contextName() }}</strong>
      </div>
      <CStatus tone="nominal" pulse>PHOENIX HOST</CStatus>
    </header>

    <main class="phoenix-host-main">
      <aside
        v-if="actionFailure"
        id="phoenix-host-action-stopped"
        class="phoenix-host-action-stopped"
        role="alert"
        aria-live="assertive"
      >
        <strong>Action stopped</strong>
        <span>{{ actionFailure.message }}</span>
        <span>Reference ID: {{ actionFailure.referenceId }}</span>
      </aside>

      <section v-if="loading" id="phoenix-host-loading" class="phoenix-host-state" role="status">
        <p class="phoenix-host-eyebrow">APPLICATION SURFACE HOST</p>
        <h1>Resolving application surface</h1>
        <p>Loading the approved catalog with same-origin credentials.</p>
      </section>

      <section
        v-else-if="bootError"
        id="phoenix-host-error"
        class="phoenix-host-state phoenix-host-state--error"
      >
        <p class="phoenix-host-eyebrow">HOST CATALOG UNAVAILABLE</p>
        <h1>Cadence rejected the application catalog.</h1>
        <p>{{ bootError.message }}</p>
        <p id="phoenix-host-error-reference">Reference ID: {{ bootError.referenceId }}</p>
        <CButton id="retry-phoenix-host" variant="primary" @click="loadCatalog">
          Retry catalog
        </CButton>
      </section>

      <template v-else-if="application && bridge && context">
        <div class="phoenix-host-titlebar">
          <div>
            <p class="phoenix-host-eyebrow">
              APPLICATIONS / {{ application.displayName.toUpperCase() }} /
              {{ application.surface.navigation.label.toUpperCase() }}
            </p>
            <h1>{{ application.surface.navigation.label }}</h1>
          </div>
          <span class="phoenix-host-release" :class="{ 'phoenix-host-release--ready': manifest }">
            {{ manifest ? "REMOTE READY" : "REMOTE CHECK" }}
          </span>
        </div>

        <div class="phoenix-host-surface">
          <div class="phoenix-host-surface__chrome">
            <span>
              {{ application.displayName }} · {{ application.surface.purpose.toUpperCase() }}
            </span>
            <span>{{ application.release.releaseId }} · {{ contextDetails() }}</span>
          </div>
          <RemoteApplicationBoundary
            :key="`${application.release.releaseId}:${mountGeneration}`"
            :application="application"
            :bridge="bridge"
            :context="context"
            @ready="recordManifest"
            @retry="remountApplication"
          />
        </div>
      </template>
    </main>
  </div>
</template>

<style scoped>
.phoenix-host-shell {
  min-height: 100vh;
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
  font-family: var(--cadence-font-sans);
}

.phoenix-host-header {
  display: grid;
  grid-template-columns: minmax(200px, 240px) 1fr auto;
  align-items: center;
  min-height: 60px;
  border-bottom: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-shell);
}

.phoenix-host-wordmark {
  display: flex;
  align-items: center;
  align-self: stretch;
  gap: 12px;
  padding: 0 20px;
  border-right: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-strong);
  font-size: 15px;
  font-weight: 760;
  letter-spacing: 0.19em;
  text-decoration: none;
}

.phoenix-host-signal {
  display: flex;
  align-items: end;
  gap: 2px;
  width: 20px;
  height: 20px;
}

.phoenix-host-signal i {
  display: block;
  width: 4px;
  background: var(--cadence-color-accent);
}

.phoenix-host-signal i:nth-child(1) {
  height: 8px;
}
.phoenix-host-signal i:nth-child(2) {
  height: 17px;
}
.phoenix-host-signal i:nth-child(3) {
  height: 12px;
}

.phoenix-host-context {
  display: grid;
  gap: 4px;
  padding: 0 24px;
}

.phoenix-host-context span,
.phoenix-host-eyebrow,
.phoenix-host-surface__chrome,
.phoenix-host-release {
  font-family: var(--cadence-font-mono);
  font-size: 10px;
  font-weight: 630;
  letter-spacing: 0.105em;
  text-transform: uppercase;
}

.phoenix-host-context span,
.phoenix-host-eyebrow,
.phoenix-host-surface__chrome {
  color: var(--cadence-color-text-muted);
}

.phoenix-host-context strong {
  color: var(--cadence-color-text-strong);
}

.phoenix-host-header > .cui-status {
  margin-right: 20px;
}

.phoenix-host-main {
  width: min(1160px, calc(100% - 48px));
  margin: 0 auto;
  padding: 38px 0 64px;
}

.phoenix-host-titlebar {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 24px;
}

.phoenix-host-eyebrow {
  margin: 0 0 9px;
  color: var(--cadence-color-accent);
}
.phoenix-host-titlebar h1,
.phoenix-host-state h1 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: clamp(30px, 4vw, 50px);
  font-weight: 620;
  letter-spacing: -0.045em;
  line-height: 0.98;
}

.phoenix-host-release {
  padding: 8px 10px;
  border: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-warning);
}

.phoenix-host-release--ready {
  border-color: var(--cadence-color-success);
  color: var(--cadence-color-success);
}

.phoenix-host-surface {
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface-inset);
}

.phoenix-host-surface__chrome {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  padding: 11px 16px;
  border-bottom: 1px solid var(--cadence-color-border);
}

.phoenix-host-state {
  max-width: 760px;
  margin: 72px auto;
  padding: 40px;
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface-inset);
}

.phoenix-host-state p:not(.phoenix-host-eyebrow) {
  margin: 20px 0 28px;
  color: var(--cadence-color-text-secondary);
}

.phoenix-host-state--error {
  border-left: 4px solid var(--cadence-color-danger);
}
.phoenix-host-state--error .phoenix-host-eyebrow {
  color: var(--cadence-color-danger);
}

.phoenix-host-action-stopped {
  display: grid;
  gap: 6px;
  margin-bottom: 20px;
  padding: 12px 16px;
  border-left: 4px solid var(--cadence-color-warning);
  background: var(--cadence-color-surface-inset);
  color: var(--cadence-color-text-secondary);
}

.phoenix-host-action-stopped strong,
.phoenix-host-action-stopped span:last-child {
  font-family: var(--cadence-font-mono);
  font-size: 10px;
  letter-spacing: 0.105em;
  text-transform: uppercase;
}

.phoenix-host-action-stopped strong {
  color: var(--cadence-color-warning);
}

@media (max-width: 700px) {
  .phoenix-host-header {
    grid-template-columns: 1fr auto;
  }
  .phoenix-host-context {
    display: none;
  }
  .phoenix-host-main {
    width: min(100% - 32px, 1160px);
    padding-top: 24px;
  }
  .phoenix-host-titlebar,
  .phoenix-host-surface__chrome {
    align-items: start;
    flex-direction: column;
  }
}
</style>
