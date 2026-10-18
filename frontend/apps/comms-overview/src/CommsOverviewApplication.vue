<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { computed, onMounted, ref, shallowRef } from "vue";
import CommsOverviewPage from "./CommsOverviewPage.vue";
import { unwrapCommsOverviewResponse, type CommsOverviewPresentation } from "./comms-overview";

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<CommsOverviewPresentation>();
const loading = ref(true);
const error = ref<string>();
let loadGeneration = 0;

const surfaceComponents = {
  overview: CommsOverviewPage,
} as const;
const renderer = computed(() =>
  Object.hasOwn(surfaceComponents, props.surface.surfaceId)
    ? surfaceComponents[props.surface.surfaceId as "overview"]
    : undefined,
);

onMounted(() => void loadSurface());

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    if (!renderer.value) throw new Error("The selected communications surface is unavailable.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    presentation.value = unwrapCommsOverviewResponse(response);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The communications overview failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}
</script>

<template>
  <div
    id="comms-overview-application"
    class="comms-overview-application"
    :data-comms-overview-surface="props.surface.surfaceId"
    data-comms-overview-renderer="CommsOverviewPage"
  >
    <section
      v-if="loading"
      id="comms-overview-loading"
      class="card min-h-80 border border-base-300 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body flex items-center justify-center gap-5 p-8 text-base-content/70">
        <span
          class="loading loading-spinner loading-md"
          aria-label="Loading communications overview"
        ></span>
        <div>
          <strong class="mb-1 block text-lg font-medium tracking-tight text-base-content"
            >Loading communications overview</strong
          >
          <p class="text-sm leading-6">
            Requesting the mission-scoped presentation from the Phoenix host.
          </p>
        </div>
      </div>
    </section>
    <section
      v-else-if="error"
      id="comms-overview-error"
      class="card border border-error/40 bg-base-200"
      aria-live="polite"
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
              >Communications overview unavailable</strong
            >
            <p class="mt-1 text-sm leading-6 text-base-content/70">{{ error }}</p>
            <button
              id="retry-comms-overview"
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
    <component v-else-if="renderer && presentation" :is="renderer" :presentation="presentation" />
  </div>
</template>
