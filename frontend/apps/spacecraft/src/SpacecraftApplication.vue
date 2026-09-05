<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import SpacecraftApplicationsPage from "./SpacecraftApplicationsPage.vue";
import SpacecraftCommanding from "./SpacecraftCommanding.vue";
import SpacecraftEdit from "./SpacecraftEdit.vue";
import SpacecraftListPage from "./SpacecraftListPage.vue";
import SpacecraftNew from "./SpacecraftNew.vue";
import SpacecraftReadiness from "./SpacecraftReadiness.vue";
import SpacecraftRouting from "./SpacecraftRouting.vue";
import SpacecraftShow from "./SpacecraftShow.vue";
import SpacecraftTelemetryDecom from "./SpacecraftTelemetryDecom.vue";
import SpacecraftTypeListPage from "./SpacecraftTypeListPage.vue";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";
import SpacecraftTypeShow from "./SpacecraftTypeShow.vue";

const props = defineProps<FullPageSurfaceProps>();

const surfaceComponents: Record<string, Component> = {
  list: SpacecraftListPage,
  new: SpacecraftNew,
  profile_list: SpacecraftTypeListPage,
  profile_new: SpacecraftTypeNew,
  profile_show: SpacecraftTypeShow,
  show: SpacecraftShow,
  edit: SpacecraftEdit,
  readiness: SpacecraftReadiness,
  routing: SpacecraftRouting,
  commanding: SpacecraftCommanding,
  applications: SpacecraftApplicationsPage,
  telemetry_decom: SpacecraftTelemetryDecom,
};

const actionBindings: Record<string, Record<string, string>> = {
  new: { validate: "validate", save: "save" },
  profile_new: { validate: "validate", save: "save" },
  edit: { validate: "validate", save: "save" },
  applications: { install: "install", disable: "disable", uninstall: "uninstall" },
  telemetry_decom: {
    change_revision: "save_configuration",
    save_catalog_revision: "save_configuration",
    enable: "request_activation",
    disable: "disable",
  },
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
    if (!selectedComponent.value) throw new Error("The selected spacecraft surface has no renderer.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    pageProps.value = pagePropsFor(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The spacecraft surface query failed.";
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
  <div id="spacecraft-remote-application">
    <CStatePanel
      v-if="loading"
      id="spacecraft-loading"
      title="Loading spacecraft surface"
      description="Requesting the Phoenix-owned presentation from the host."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="spacecraft-error"
      title="Spacecraft surface unavailable"
      :description="error"
      tone="error"
      aria-live="assertive"
    >
      <template #action>
        <CButton id="retry-spacecraft" size="sm" @click="loadSurface"> Retry query </CButton>
      </template>
    </CStatePanel>
    <div v-else-if="selectedComponent && pageProps" :data-surface-id="props.surface.surfaceId">
      <component :is="selectedComponent" v-bind="pageProps" v-on="listeners" />
    </div>
  </div>
</template>
