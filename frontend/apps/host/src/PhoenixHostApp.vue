<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  FrontendApplicationCatalog,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { CButton, CStatus } from "@cadence/ui";
import { onMounted, ref, shallowRef } from "vue";
import RemoteApplicationBoundary from "./RemoteApplicationBoundary.vue";
import {
  loadPhoenixMissionCatalog,
  selectCommsOverviewApplication,
  type PhoenixHostConfig,
} from "./phoenix-catalog-client";
import { createHttpHostBridge } from "./http-host-bridge";

const props = withDefaults(
  defineProps<PhoenixHostConfig & { fetcher?: typeof globalThis.fetch }>(),
  { fetcher: undefined },
);

const catalog = shallowRef<FrontendApplicationCatalog>();
const application = shallowRef<CatalogApplication>();
const bridge = shallowRef<HostBridge>();
const context = shallowRef<HostContext>();
const manifest = shallowRef<FirstPartyApplicationManifest>();
const bootError = ref<string>();
const loading = ref(true);
const mountGeneration = ref(0);
let loadGeneration = 0;

onMounted(loadCatalog);

async function loadCatalog(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  bootError.value = undefined;
  manifest.value = undefined;
  catalog.value = undefined;
  application.value = undefined;
  bridge.value = undefined;
  context.value = undefined;

  try {
    const nextCatalog = await loadPhoenixMissionCatalog(
      { missionId: props.missionId, catalogUrl: props.catalogUrl },
      { fetch: props.fetcher },
    );
    const nextApplication = selectCommsOverviewApplication(nextCatalog);
    if (generation !== loadGeneration) return;

    catalog.value = nextCatalog;
    application.value = nextApplication;
    context.value = nextCatalog.session.context;
    bridge.value = createHttpHostBridge(nextCatalog.session);
    mountGeneration.value += 1;
  } catch (reason) {
    if (generation !== loadGeneration) return;
    bootError.value = reason instanceof Error ? reason.message : "The mission host failed to load.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

function remountApplication(): void {
  manifest.value = undefined;
  mountGeneration.value += 1;
}

function recordManifest(value: FirstPartyApplicationManifest): void {
  manifest.value = value;
}

function missionHref(): string {
  return `/missions/${encodeURIComponent(props.missionId)}/comms`;
}
</script>

<template>
  <div id="cadence-phoenix-host" class="phoenix-host-shell">
    <header class="phoenix-host-header">
      <a id="phoenix-host-home" class="phoenix-host-wordmark" :href="missionHref()">
        <span class="phoenix-host-signal" aria-hidden="true"><i></i><i></i><i></i></span>
        <span>CADENCE</span>
      </a>
      <div class="phoenix-host-context">
        <span>MISSION CONTEXT</span>
        <strong>{{ context?.missionName ?? "RESOLVING" }}</strong>
      </div>
      <CStatus tone="nominal" pulse>PHOENIX HOST</CStatus>
    </header>

    <main class="phoenix-host-main">
      <section v-if="loading" id="phoenix-host-loading" class="phoenix-host-state" role="status">
        <p class="phoenix-host-eyebrow">MISSION APPLICATION HOST</p>
        <h1>Resolving communications surface</h1>
        <p>Loading the approved mission catalog with same-origin credentials.</p>
      </section>

      <section
        v-else-if="bootError"
        id="phoenix-host-error"
        class="phoenix-host-state phoenix-host-state--error"
      >
        <p class="phoenix-host-eyebrow">HOST CATALOG UNAVAILABLE</p>
        <h1>Cadence rejected the mission application catalog.</h1>
        <p>{{ bootError }}</p>
        <CButton id="retry-phoenix-host" variant="primary" @click="loadCatalog">
          Retry catalog
        </CButton>
      </section>

      <template v-else-if="application && bridge && context">
        <div class="phoenix-host-titlebar">
          <div>
            <p class="phoenix-host-eyebrow">APPLICATIONS / COMMS OVERVIEW</p>
            <h1>{{ application.surface.navigation.label }}</h1>
          </div>
          <span class="phoenix-host-release" :class="{ 'phoenix-host-release--ready': manifest }">
            {{ manifest ? "REMOTE READY" : "REMOTE CHECK" }}
          </span>
        </div>

        <div class="phoenix-host-surface">
          <div class="phoenix-host-surface__chrome">
            <span>TRUSTED FIRST-PARTY SURFACE</span>
            <span>{{ application.release.releaseId }} · MISSION {{ context.missionId }}</span>
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
