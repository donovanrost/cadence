<script setup lang="ts">
import {
  createFederatedActionLifecycle,
  type FullPageSurfaceProps,
  type HostActionReceipt,
} from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import CatalogArtifactShowPage from "./CatalogArtifactShowPage.vue";
import CatalogDatabaseNew from "./CatalogDatabaseNew.vue";
import CatalogDatabaseShow from "./CatalogDatabaseShow.vue";
import CatalogImportRunShow from "./CatalogImportRunShow.vue";
import CatalogIndex from "./CatalogIndex.vue";
import CatalogRevisionShow from "./CatalogRevisionShow.vue";
import MissionApplicationsPage from "./MissionApplicationsPage.vue";
import MissionList from "./MissionList.vue";
import MissionNew from "./MissionNew.vue";
import MissionOverview from "./MissionOverview.vue";

const props = defineProps<FullPageSurfaceProps>();

const surfaceComponents: Record<string, Component> = {
  mission_list: MissionList,
  mission_new: MissionNew,
  mission_overview: MissionOverview,
  mission_applications: MissionApplicationsPage,
  catalog_index: CatalogIndex,
  catalog_database_new: CatalogDatabaseNew,
  catalog_database_show: CatalogDatabaseShow,
  catalog_revision_show: CatalogRevisionShow,
  catalog_artifact_show: CatalogArtifactShowPage,
  catalog_import_run_show: CatalogImportRunShow,
};

const actionBindings: Record<string, Record<string, string>> = {
  mission_new: { validate: "validate", save: "save" },
  mission_applications: { install: "install", disable: "disable", uninstall: "uninstall" },
  catalog_database_new: {
    validate: "validate",
    save: "save",
  },
  catalog_database_show: {
    validate: "validate",
    save: "save",
  },
  catalog_artifact_show: { reimport: "reimport" },
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
    if (!selectedComponent.value) throw new Error("The selected mission surface has no renderer.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    pageProps.value = pagePropsFor(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The mission surface query failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

const listeners = computed(() =>
  Object.fromEntries(
    Object.entries(selectedBindings.value).map(([event, actionId]) => [
      event,
      (input: unknown) => void actionLifecycle.execute(actionId, input ?? {}),
    ]),
  ),
);

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
  <div id="mission-catalog-application">
    <section
      v-if="loading"
      id="mission-catalog-loading"
      class="card min-h-80 border border-base-300 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body flex items-center justify-center gap-5 p-8 text-base-content/70">
        <span
          class="loading loading-spinner loading-md"
          aria-label="Loading mission and catalog surface"
        ></span>
        <div>
          <strong class="mb-1 block text-lg font-medium tracking-tight text-base-content"
            >Loading mission and catalog surface</strong
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
      id="mission-catalog-error"
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
              >Mission and catalog surface unavailable</strong
            >
            <p class="mt-1 text-sm leading-6 text-base-content/70">{{ error }}</p>
            <button
              id="retry-mission-catalog"
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
        id="mission-catalog-action-loading"
        role="status"
        aria-live="polite"
        class="mb-4 border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
      >
        Sending the mission and catalog action to Phoenix…
      </aside>
      <aside
        v-if="actionError"
        id="mission-catalog-action-error"
        role="alert"
        aria-live="assertive"
        class="mb-4 border border-error/40 bg-error/10 px-4 py-3 text-sm text-error"
      >
        {{ actionError }}
      </aside>
      <aside
        v-if="actionNotice && actionReceipt"
        id="mission-catalog-action-notice"
        role="status"
        aria-live="polite"
        :data-receipt-id="actionReceipt.receiptId"
        :data-completed-at="actionReceipt.completedAt"
        class="mb-4 border border-success/40 bg-success/10 px-4 py-3 text-sm text-base-content"
      >
        {{ actionNotice }} Receipt {{ actionReceipt.receiptId }} completed at
        {{ actionReceipt.completedAt }}.
      </aside>
      <component :is="selectedComponent" v-bind="pageProps" v-on="listeners" />
    </div>
  </div>
</template>
