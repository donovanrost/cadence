<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onMounted, ref, shallowRef } from "vue";
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
    "cancel-upload": "cancel-upload",
  },
  catalog_database_show: {
    "toggle-revision-form": "toggle-revision-form",
    validate: "validate",
    save: "save",
    "cancel-upload": "cancel-upload",
  },
  catalog_artifact_show: { reimport: "reimport" },
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
      (input: unknown) => execute(actionId, input),
    ]),
  ),
);

function pagePropsFor(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) return {};
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
  <div id="mission-catalog-application">
    <CStatePanel
      v-if="loading"
      id="mission-catalog-loading"
      title="Loading mission and catalog surface"
      description="Requesting the Phoenix-owned presentation from the host."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="mission-catalog-error"
      title="Mission and catalog surface unavailable"
      :description="error"
      tone="error"
      aria-live="assertive"
    >
      <template #action>
        <CButton id="retry-mission-catalog" size="sm" @click="loadSurface"> Retry query </CButton>
      </template>
    </CStatePanel>
    <div v-else-if="selectedComponent && pageProps" :data-surface-id="props.surface.surfaceId">
      <component :is="selectedComponent" v-bind="pageProps" v-on="listeners" />
    </div>
  </div>
</template>
