<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onErrorCaptured, ref, shallowRef, watch } from "vue";
import {
  admitFormSurface,
  TransportCreation,
  RoutingCreation,
  GroundStationEditor,
  FormActionFailure,
} from "@cadence/communications/form-surfaces";
import type { Component } from "vue";
import CommsCanonicalSurface from "./CommsCanonicalSurface.vue";
import {
  admitProviderSurface,
  ProviderList,
  ProviderCreation,
  ProviderDetail,
} from "@cadence/communications/providers";

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
  provider_list: ProviderList,
  provider_new: ProviderCreation,
  provider_show: ProviderDetail,
  transport_new: TransportCreation,
  routing_new: RoutingCreation,
  ground_station_new: GroundStationEditor,
  ground_station_edit: GroundStationEditor,
};

const pageProps = shallowRef<Record<string, unknown>>();
const loading = ref(true);
const error = ref<string>();
onErrorCaptured(() => {
  error.value = "The Communications view could not be displayed.";
  pageProps.value = undefined;
  return false;
});
let loadGeneration = 0;

const selectedComponent = computed(() =>
  Object.hasOwn(surfaceComponents, props.surface.surfaceId)
    ? surfaceComponents[props.surface.surfaceId]
    : undefined,
);

watch(
  () => [props.surface, props.context, props.bridge, props.application],
  () => {
    void loadSurface();
  },
  { immediate: true },
);

onBeforeUnmount(() => {
  ++loadGeneration;
});

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
  } catch {
    if (generation !== loadGeneration) return;
    error.value = "The Comms surface could not be loaded. Try refreshing the approved page.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

function scopedPort() {
  const { bridge, application, context, surface } = props;
  return {
    execute: async (actionId: string, input: Record<string, unknown>) => {
      if (!surface.actions.includes(actionId)) throw new FormActionFailure("rejected");
      try {
        return await bridge.execute({
          applicationKey: application.applicationKey,
          applicationVersion: application.applicationVersion,
          actionId,
          input,
          context,
        });
      } catch (reason) {
        const confirmed =
          isRecord(reason) &&
          typeof reason.status === "number" &&
          reason.status >= 400 &&
          reason.status < 500 &&
          [
            "invalid_input",
            "invalid_scope",
            "forbidden",
            "mission_not_found",
            "unsupported_action",
          ].includes(String(reason.code));
        throw new FormActionFailure(confirmed ? "rejected" : "unknown");
      }
    },
    query: () =>
      bridge.query({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      }),
    navigate: (href: string) => {
      if (bridge.navigate) bridge.navigate(href);
      else window.location.assign(href);
    },
  };
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

  if (["provider_list", "provider_new", "provider_show"].includes(props.surface.surfaceId)) {
    if (typeof props.context.missionId !== "string") throw new Error("A mission is required.");
    const context = { missionId: props.context.missionId };
    const admitted = admitProviderSurface(
      props.surface.surfaceId,
      props.surface.dataContract.version,
      { navigation, data },
      context,
    );
    return { ...admitted, port: scopedPort(), context };
  }

  if (
    ["transport_new", "routing_new", "ground_station_new", "ground_station_edit"].includes(
      props.surface.surfaceId,
    )
  ) {
    if (typeof props.context.missionId !== "string")
      throw new Error("A mission is required for a Communications form.");
    const form = admitFormSurface(
      props.surface.surfaceId,
      props.surface.dataContract.version,
      { navigation, data },
      { missionId: props.context.missionId },
    );
    return { ...form, port: scopedPort(), context: { missionId: props.context.missionId } };
  }

  return {
    surfaceId: props.surface.surfaceId,
    version: props.surface.dataContract.version,
    context: props.context,
    payload: { navigation, data },
  };
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
      <component :is="selectedComponent" v-bind="pageProps" @retry="loadSurface" />
    </div>
  </div>
</template>
