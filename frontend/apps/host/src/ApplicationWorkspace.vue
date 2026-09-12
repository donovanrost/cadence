<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  FrontendApplicationCatalog,
  HostActivityEvent,
} from "@cadence/plugin-sdk";
import { CadenceButton, CadenceStatus, CadenceTooltip } from "@cadence/ui";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import { loadFrontendApplicationCatalog } from "./catalog-client";
import { createHttpHostBridge, type HttpHostBridge } from "./http-host-bridge";
import RemoteApplicationBoundary from "./RemoteApplicationBoundary.vue";

const pageUrl = new URL(window.location.href);
const requestedApplication = pageUrl.searchParams.get("application")?.trim() || undefined;
const requestedRelease =
  pageUrl.searchParams.get("release") === "previous" ? "previous" : "current";
const requestedScenario = pageUrl.searchParams.get("scenario") ?? undefined;

const catalog = shallowRef<FrontendApplicationCatalog>();
const bridge = shallowRef<HttpHostBridge>();
const manifest = shallowRef<FirstPartyApplicationManifest>();
const bootError = ref<string>();
const activeApplicationKey = ref(requestedApplication);
const activity = ref<HostActivityEvent[]>([]);
const activityOpen = ref(true);
const mountGeneration = ref(0);
let catalogGeneration = 0;
let currentBridgeOwner: HttpHostBridge | undefined;
let stopListening: (() => void) | undefined;

const context = computed(() => catalog.value?.session.context);
const applications = computed(() =>
  [...(catalog.value?.applications ?? [])].sort(
    (left, right) => left.surface.navigation.order - right.surface.navigation.order,
  ),
);
const activeApplication = computed(() =>
  applications.value.find(
    (application) => application.applicationKey === activeApplicationKey.value,
  ),
);

const contractLabel = computed(() => {
  if (!catalog.value) return "CATALOG CHECK";
  if (!manifest.value) return "REMOTE CHECK";
  return `APP ${manifest.value.compatibility.cadenceApplicationContract} · SURFACE ${manifest.value.compatibility.cadenceSurfaceContract} · THEME ${manifest.value.compatibility.cadenceThemeContract}`;
});

const operatorTooltip = computed(() => {
  const actor = context.value?.actor;
  return actor ? `${actor.displayName} · ${actor.permissions.join(" · ")}` : "Resolving operator";
});

onMounted(loadCatalog);
onBeforeUnmount(() => {
  catalogGeneration += 1;
  abandonCurrentBridge();
});

async function loadCatalog(): Promise<void> {
  const generation = ++catalogGeneration;
  abandonCurrentBridge();
  bootError.value = undefined;
  manifest.value = undefined;
  catalog.value = undefined;

  try {
    const nextCatalog = await loadFrontendApplicationCatalog({
      release: requestedRelease,
      ...(requestedScenario === undefined ? {} : { scenario: requestedScenario }),
    });
    if (generation !== catalogGeneration) return;
    catalog.value = nextCatalog;

    if (!nextCatalog.applications.some(matchesActiveApplication))
      activeApplicationKey.value = nextCatalog.applications[0]?.applicationKey;

    const nextApplication = nextCatalog.applications.find(matchesActiveApplication);
    if (!nextApplication) throw new Error("The host catalog did not provide an application.");

    const nextBridge = createHttpHostBridge(nextCatalog.session, nextApplication);
    if (generation !== catalogGeneration) {
      nextBridge.invalidate();
      return;
    }
    installBridge(nextBridge);

    mountGeneration.value += 1;
  } catch (reason) {
    if (generation !== catalogGeneration) return;
    catalog.value = undefined;
    bootError.value = messageFor(reason, "The host catalog could not be loaded.");
  }
}

function matchesActiveApplication(application: CatalogApplication): boolean {
  return application.applicationKey === activeApplicationKey.value;
}

function selectApplication(application: CatalogApplication): void {
  if (activeApplicationKey.value === application.applicationKey) return;
  activeApplicationKey.value = application.applicationKey;
  manifest.value = undefined;
  const currentCatalog = catalog.value;
  if (!currentCatalog) return;
  abandonCurrentBridge();
  const nextBridge = createHttpHostBridge(currentCatalog.session, application);
  installBridge(nextBridge);
  mountGeneration.value += 1;
  pageUrl.searchParams.set("application", application.applicationKey);
  window.history.replaceState({}, "", pageUrl);
}

function remountActiveApplication(): void {
  manifest.value = undefined;
  const currentCatalog = catalog.value;
  const application = activeApplication.value;
  if (currentCatalog && application) {
    abandonCurrentBridge();
    installBridge(createHttpHostBridge(currentCatalog.session, application));
  } else {
    abandonCurrentBridge();
  }
  mountGeneration.value += 1;
}

function installBridge(nextBridge: HttpHostBridge): void {
  currentBridgeOwner = nextBridge;
  bridge.value = nextBridge;
  stopListening = nextBridge.subscribe(recordActivity);
}

function abandonCurrentBridge(): void {
  const abandonedBridge = currentBridgeOwner;
  const unsubscribe = stopListening;
  currentBridgeOwner = undefined;
  stopListening = undefined;
  bridge.value = undefined;
  unsubscribe?.();
  abandonedBridge?.invalidate();
}

function recordManifest(value: FirstPartyApplicationManifest): void {
  manifest.value = value;
}

function recordActivity(event: HostActivityEvent): void {
  activity.value = [event, ...activity.value].slice(0, 12);
}

function activityLabel(event: HostActivityEvent): string {
  return event.contractId;
}

function activityTime(value: string): string {
  return new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date(value));
}

function initials(displayName: string | undefined): string {
  return (displayName ?? "--")
    .split(" ")
    .map((part) => part[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

function contextLabel(): string {
  return context.value ? `${context.value.scope.toUpperCase()} CONTEXT` : "CONTEXT";
}

function contextName(): string {
  const activeContext = context.value;
  if (!activeContext) return "RESOLVING";

  switch (activeContext.scope) {
    case "organization":
      return activeContext.organizationId;
    case "user":
    case "admin":
      return activeContext.actor.displayName;
    case "mission":
      return activeContext.missionName;
    case "spacecraft":
      return activeContext.spacecraftName;
  }
}

function contextDetails(): string {
  const activeContext = context.value;
  if (!activeContext) return "RESOLVING";

  switch (activeContext.scope) {
    case "organization":
      return activeContext.organizationId;
    case "user":
      return activeContext.userId;
    case "admin":
      return "GLOBAL";
    case "mission":
      return activeContext.missionId;
    case "spacecraft":
      return `${activeContext.missionId} · ${activeContext.spacecraftId}`;
  }
}

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <div id="cadence-host" class="host-shell">
    <header class="topbar">
      <div class="wordmark" aria-label="Cadence application host">
        <span class="wordmark__signal" aria-hidden="true"><i></i><i></i><i></i></span>
        <span>CADENCE / HOST</span>
      </div>

      <div class="host-context">
        <span class="host-context__label">{{ contextLabel() }}</span>
        <strong>{{ contextName() }}</strong>
        <span class="host-context__separator">/</span>
        <span>{{ contextDetails() }}</span>
      </div>

      <div class="operator-context">
        <CadenceStatus
          class="operator-context__status"
          :tone="context ? 'nominal' : 'warning'"
          pulse
        >
          {{ context ? "CATALOG AUTHENTICATED" : "CATALOG CHECK" }}
        </CadenceStatus>
        <CadenceTooltip align="end" :content="operatorTooltip">
          <span id="operator-menu" aria-label="Current catalog actor">
            {{ initials(context?.actor.displayName) }}
          </span>
        </CadenceTooltip>
      </div>
    </header>

    <aside class="rail" aria-label="Admitted applications">
      <div class="rail__section-label">ADMITTED APPLICATIONS</div>
      <nav id="application-navigation">
        <button
          v-for="application in applications"
          :id="`application-${application.applicationKey}`"
          :key="application.applicationKey"
          type="button"
          :class="{ active: activeApplicationKey === application.applicationKey }"
          @click="selectApplication(application)"
        >
          <span
            :class="activeApplicationKey === application.applicationKey ? 'active-mark' : undefined"
          ></span>
          {{ application.displayName }} / {{ application.surface.navigation.label }}
        </button>
        <span v-if="applications.length === 0" class="rail__loading">Resolving catalog…</span>
      </nav>

      <div class="rail__foot">
        <span>HOST CONTRACT</span>
        <strong>{{ contractLabel }}</strong>
      </div>
    </aside>

    <main class="workspace">
      <section v-if="bootError" id="catalog-error" class="host-boot-error">
        <p class="eyebrow">Catalog unavailable</p>
        <h1>The application catalog was rejected.</h1>
        <p>{{ bootError }}</p>
        <CadenceButton id="retry-catalog" variant="primary" @click="loadCatalog"
          >Retry catalog</CadenceButton
        >
      </section>

      <template v-else-if="activeApplication && bridge && context">
        <div class="workspace__head">
          <div>
            <p class="breadcrumb">
              {{ activeApplication.applicationKey.toUpperCase() }} /
              {{ activeApplication.surface.surfaceId.toUpperCase() }}
            </p>
            <h1>{{ activeApplication.surface.navigation.label }}</h1>
          </div>
          <div class="runtime-badge" :class="{ 'runtime-badge--ready': manifest }">
            <span></span>
            {{ manifest ? "REMOTE READY" : "REMOTE CHECK" }}
          </div>
        </div>

        <div class="surface-frame">
          <div class="surface-frame__chrome">
            <span>ADMITTED FEDERATED SURFACE</span>
            <span>
              {{ activeApplication.package.packageId }}@{{ activeApplication.package.version }} ·
              RELEASE {{ activeApplication.release.releaseId }}
            </span>
          </div>
          <RemoteApplicationBoundary
            :key="`${activeApplication.applicationKey}:${activeApplication.release.releaseId}:${mountGeneration}`"
            :application="activeApplication"
            :bridge="bridge"
            :context="context"
            :fallback-href="pageUrl.href"
            @ready="recordManifest"
            @retry="remountActiveApplication"
          />
        </div>
      </template>
    </main>

    <aside class="activity-dock" :class="{ 'activity-dock--closed': !activityOpen }">
      <button
        id="activity-toggle"
        class="activity-dock__head"
        type="button"
        :aria-expanded="activityOpen"
        @click="activityOpen = !activityOpen"
      >
        <span>HOST ACTIVITY</span>
        <b>{{ activityOpen ? "COLLAPSE" : "EXPAND" }}</b>
      </button>

      <div v-if="activityOpen" id="host-activity" class="activity-list">
        <div v-if="activity.length === 0" class="activity-empty">
          <span class="activity-empty__pulse"></span>
          Waiting for contract traffic
        </div>
        <article v-for="event in activity" :key="event.eventId" class="activity-item">
          <div class="activity-item__line">
            <span :class="['activity-state', `activity-state--${event.status}`]"></span>
            <strong>{{ activityLabel(event) }}</strong>
            <time>{{ activityTime(event.occurredAt) }}</time>
          </div>
          <div class="activity-item__meta">
            <span>{{ event.kind }}</span>
            <span>{{ event.status }}</span>
          </div>
        </article>
      </div>
    </aside>
  </div>
</template>
