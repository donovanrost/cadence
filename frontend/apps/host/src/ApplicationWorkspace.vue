<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  FrontendApplicationCatalog,
  HostActivityEvent,
} from "@cadence/plugin-sdk";
import { CButton, CStatus, CTooltip } from "@cadence/ui";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import { loadFrontendApplicationCatalog } from "./catalog-client";
import { createHttpHostBridge, type HttpHostBridge } from "./http-host-bridge";
import RemoteApplicationBoundary from "./RemoteApplicationBoundary.vue";

const emit = defineEmits<{
  navigate: [path: string];
}>();

const pageUrl = new URL(window.location.href);
const requestedApplication = pageUrl.searchParams.get("application");
const requestedRelease =
  pageUrl.searchParams.get("release") === "previous" ? "previous" : "current";
const requestedScenario = pageUrl.searchParams.get("scenario") ?? undefined;

const catalog = shallowRef<FrontendApplicationCatalog>();
const bridge = shallowRef<HttpHostBridge>();
const manifest = shallowRef<FirstPartyApplicationManifest>();
const bootError = ref<string>();
const activeApplicationKey = ref(requestedApplication ?? "telemetry_decom");
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
      scenario: requestedScenario,
    });
    if (generation !== catalogGeneration) return;
    catalog.value = nextCatalog;

    if (!nextCatalog.applications.some(matchesActiveApplication)) {
      activeApplicationKey.value = nextCatalog.applications[0]?.applicationKey ?? "";
    }

    const nextApplication = nextCatalog.applications.find(matchesActiveApplication);
    if (!nextApplication)
      throw new Error("The host catalog did not provide an active application.");

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
  if (event.contractId === "cadence.packet_bindings.manage") return "Packet data query";
  if (event.contractId === "cadence.contract_probe.snapshot") return "Contract probe query";
  if (event.contractId === "save_packet_bindings") return "Save packet bindings";
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

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <div id="cadence-host" class="host-shell">
    <header class="topbar">
      <a
        class="wordmark"
        href="/admin"
        aria-label="Cadence administration"
        @click.prevent="emit('navigate', '/admin')"
      >
        <span class="wordmark__signal" aria-hidden="true"><i></i><i></i><i></i></span>
        <span>CADENCE</span>
      </a>

      <div class="mission-context">
        <span class="mission-context__label">ACTIVE MISSION</span>
        <strong>{{ context?.missionName ?? "RESOLVING" }}</strong>
        <span class="mission-context__separator">/</span>
        <span>{{ context?.spacecraftName ?? "HOST CONTEXT" }}</span>
      </div>

      <div class="operator-context">
        <CStatus class="operator-context__status" :tone="context ? 'nominal' : 'warning'" pulse>
          {{ context ? "SESSION AUTHENTICATED" : "SESSION CHECK" }}
        </CStatus>
        <CTooltip align="end" :content="operatorTooltip">
          <button id="operator-menu" type="button" aria-label="Open operator menu">
            {{ initials(context?.actor.displayName) }}
          </button>
        </CTooltip>
      </div>
    </header>

    <aside class="rail" aria-label="Primary navigation">
      <div class="rail__section-label">MISSION</div>
      <nav>
        <button type="button" @click="emit('navigate', '/admin')"><span>00</span>Admin</button>
        <a href="#"><span>01</span>Overview</a>
        <a href="#"><span>02</span>Operations</a>
        <a href="#"><span>03</span>Telemetry</a>
      </nav>
      <div class="rail__section-label rail__section-label--apps">APPLICATIONS</div>
      <nav id="application-navigation">
        <button
          v-for="application in applications"
          :id="`open-${application.applicationKey}`"
          :key="application.applicationKey"
          type="button"
          :class="{ active: activeApplicationKey === application.applicationKey }"
          @click="selectApplication(application)"
        >
          <span
            :class="activeApplicationKey === application.applicationKey ? 'active-mark' : undefined"
          ></span>
          {{ application.displayName }}
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
        <p class="eyebrow">Host catalog unavailable</p>
        <h1>Cadence rejected the application catalog.</h1>
        <p>{{ bootError }}</p>
        <CButton id="retry-catalog" variant="primary" @click="loadCatalog">Retry catalog</CButton>
      </section>

      <template v-else-if="activeApplication && bridge && context">
        <div class="workspace__head">
          <div>
            <p class="breadcrumb">
              APPLICATIONS / {{ activeApplication.displayName.toUpperCase() }}
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
            <span>TRUSTED FIRST-PARTY SURFACE</span>
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
