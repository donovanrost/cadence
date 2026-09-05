<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { computed, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import CommsCanonicalSurface from "./CommsCanonicalSurface.vue";
import CommsProviderList from "./CommsProviderList.vue";
import CommsProviderNew from "./CommsProviderNew.vue";
import CommsProviderShow from "./CommsProviderShow.vue";
import CommsTransportNew from "./CommsTransportNew.vue";
import CommsRoutingNew from "./CommsRoutingNew.vue";
import CommsGroundStationForm from "./CommsGroundStationForm.vue";

const props = defineProps<FullPageSurfaceProps>();

const surfaceComponents: Record<string, Component> = {
  overview: CommsCanonicalSurface,
  validation: CommsCanonicalSurface,
  transports: CommsCanonicalSurface,
  transport: CommsCanonicalSurface,
  routing: CommsCanonicalSurface,
  routing_detail: CommsCanonicalSurface,
  ground_stations: CommsCanonicalSurface,
  ground_station: CommsCanonicalSurface,
  provider_list: CommsProviderList,
  provider_new: CommsProviderNew,
  provider_show: CommsProviderShow,
  transport_new: CommsTransportNew,
  routing_new: CommsRoutingNew,
  ground_station_new: CommsGroundStationForm,
  ground_station_edit: CommsGroundStationForm,
};

const pageProps = shallowRef<Record<string, unknown>>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
let loadGeneration = 0;

const selectedComponent = computed(() => surfaceComponents[props.surface.surfaceId]);

onMounted(loadSurface);

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  pageProps.value = undefined;

  try {
    if (!selectedComponent.value) throw new Error("The selected Comms surface has no renderer.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    pageProps.value = pagePropsFor(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The Comms surface query failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function executeAction(actionId: string, input: unknown = {}): Promise<void> {
  if (!props.surface.actions.includes(actionId)) {
    error.value = `The ${actionId} action is not declared for this Comms surface.`;
    return;
  }

  if (actionPending.value) return;
  actionPending.value = true;
  error.value = undefined;

  try {
    const receipt = await props.bridge.execute({
      applicationKey: props.application.applicationKey,
      applicationVersion: props.application.applicationVersion,
      actionId,
      input,
      context: props.context,
    });

    if (actionId === "save") {
      const href = actionResultHref(receipt);
      if (href) {
        window.location.assign(href);
        return;
      }
    }

    if (actionId === "validate") return;
    await loadSurface();
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : `The ${actionId} action failed.`;
  } finally {
    actionPending.value = false;
  }
}

function saveActionId(): string {
  return props.surface.surfaceId === "provider_new" ? "create_provider" : "save";
}

function actionResultHref(value: unknown): string | null {
  if (!isRecord(value)) return null;
  const result = isRecord(value.result) ? value.result : value;
  const navigation = isRecord(result.navigation) ? result.navigation : undefined;
  const href = navigation?.href ?? result.redirect ?? result.href;
  return typeof href === "string" && href.startsWith("/missions/") ? href : null;
}

function providerActionInput(): Record<string, string> {
  const provider = pageProps.value?.provider;
  if (isRecord(provider) && typeof provider.provider_id === "string") {
    return { provider_id: provider.provider_id };
  }
  throw new Error("The provider action payload is missing provider_id.");
}

function pagePropsFor(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("The Comms surface response is invalid.");

  const data = isRecord(value.trusted_surface)
    ? isRecord(value.trusted_surface.data)
      ? value.trusted_surface.data
      : value.trusted_surface
    : isRecord(value.data)
      ? value.data
      : value;
  const navigation = isRecord(value.navigation) ? value.navigation : undefined;

  if (!navigation || !isValidNavigation(navigation)) {
    throw new Error("The Comms surface navigation is invalid.");
  }

  if (props.surface.surfaceId === "provider_list") {
    if (!isRecord(data.presentation)) {
      throw new Error("The Comms provider list response is invalid.");
    }
    return { presentation: data.presentation };
  }

  if (props.surface.surfaceId === "provider_new" || props.surface.surfaceId === "provider_show") {
    return data;
  }

  if (
    ["transport_new", "routing_new", "ground_station_new", "ground_station_edit"].includes(
      props.surface.surfaceId,
    )
  ) {
    return data;
  }

  return { surfaceId: props.surface.surfaceId, payload: { navigation, data } };
}

function isValidNavigation(value: Record<string, unknown>): boolean {
  return (
    typeof value.fallback_href === "string" &&
    Array.isArray(value.breadcrumbs) &&
    value.breadcrumbs.every(validBreadcrumb)
  );
}

function validBreadcrumb(value: unknown): boolean {
  return (
    isRecord(value) &&
    typeof value.label === "string" &&
    (value.href === null || typeof value.href === "string")
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <div id="comms-application" class="comms-application">
    <section
      v-if="loading"
      id="comms-application-loading"
      class="card min-h-80 border border-base-300 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body flex items-center justify-center gap-5 p-8 text-base-content/70">
        <span
          class="loading loading-spinner loading-md"
          aria-label="Loading communications surface"
        ></span>
        <div>
          <strong class="mb-1 block text-lg font-medium tracking-tight text-base-content"
            >Loading communications surface</strong
          >
          <p class="text-sm leading-6">
            Requesting the mission-scoped presentation from the Phoenix host.
          </p>
        </div>
      </div>
    </section>
    <section
      v-else-if="error"
      id="comms-application-error"
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
              >Communications surface unavailable</strong
            >
            <p class="mt-1 text-sm leading-6 text-base-content/70">{{ error }}</p>
            <button
              id="retry-comms-application"
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
      <component
        :is="selectedComponent"
        v-bind="pageProps"
        @save="executeAction(saveActionId(), $event)"
        @validate="executeAction('validate', $event)"
        @validate-provider="executeAction('validate_provider', providerActionInput())"
        @sync-provider="executeAction('sync_provider', providerActionInput())"
        @archive-provider="executeAction('archive_provider', providerActionInput())"
      />
    </div>
  </div>
</template>
