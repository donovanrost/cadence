<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { onBeforeUnmount, onErrorCaptured, shallowRef, watch } from "vue";
import type { Component } from "vue";
import FullPageSurface from "./FullPageSurface.vue";
import { createHostContributionBootstrap } from "./first-party-composition";
import { loadFederatedApplication } from "./remote-loader";
import { fullPageSurfaceProps } from "@cadence/plugin-sdk";
import { reportFrontendFailure, type FrontendFailureKind } from "./shell/frontend-diagnostics";

const props = defineProps<{
  application: CatalogApplication;
  bridge: HostBridge;
  context: HostContext;
  fallbackHref: string;
}>();

const emit = defineEmits<{
  ready: [manifest: FirstPartyApplicationManifest];
  retry: [];
}>();

const component = shallowRef<Component>();
const error = shallowRef<{ message: string; referenceId: string }>();
let loadGeneration = 0;
let loadController: AbortController | undefined;
const contributionBootstrap = createHostContributionBootstrap();

watch(() => props.application, loadApplication, { immediate: true });

onBeforeUnmount(() => {
  loadGeneration += 1;
  loadController?.abort(new Error("Remote application boundary unmounted."));
});

onErrorCaptured((reason) => {
  loadGeneration += 1;
  loadController?.abort(new Error("Remote application mount failed."));
  component.value = undefined;
  error.value = failureFor("The approved application failed after mounting.", reason, "render");
  return false;
});

async function loadApplication(): Promise<void> {
  const generation = ++loadGeneration;
  loadController?.abort(new Error("A newer remote application load superseded this load."));
  const controller = new AbortController();
  loadController = controller;
  component.value = undefined;
  error.value = undefined;

  try {
    const remote = await loadFederatedApplication(props.application, undefined, {
      signal: controller.signal,
    });
    if (generation !== loadGeneration || controller.signal.aborted) return;
    const contribution = contributionBootstrap.register(props.application, remote);
    component.value = contribution.default;
    emit("ready", contribution.manifest);
  } catch (reason) {
    if (generation !== loadGeneration || controller.signal.aborted) return;
    error.value = failureFor(
      "The approved application release could not be loaded.",
      reason,
      "load",
    );
  } finally {
    if (loadController === controller) loadController = undefined;
  }
}

function failureFor(
  message: string,
  reason: unknown,
  kind: FrontendFailureKind,
): { message: string; referenceId: string } {
  const diagnostic = reportFrontendFailure(
    {
      boundary: "federation",
      contributionId: `${props.application.applicationKey}.${props.application.surface.surfaceId}`,
      releaseId: props.application.release.releaseId,
    },
    kind,
    reason,
  );
  return { message, referenceId: diagnostic.id };
}
</script>

<template>
  <section
    v-if="error"
    id="remote-error"
    class="alert alert-error m-6 flex flex-col items-start gap-3"
    role="alert"
    aria-live="assertive"
  >
    <h2 class="text-lg font-semibold">{{ application.displayName }} was contained.</h2>
    <p id="remote-error-message">{{ error.message }}</p>
    <p id="remote-error-reference" class="font-mono text-xs">
      Reference ID: {{ error.referenceId }}
    </p>
    <p class="text-sm">The current Cadence page remains available.</p>
    <button id="retry-remote" type="button" class="btn btn-primary btn-sm" @click="$emit('retry')">
      Retry approved release
    </button>
    <a id="remote-fallback" class="link text-sm" :href="fallbackHref">Return to Cadence</a>
  </section>

  <section
    v-else-if="!component"
    id="remote-loading"
    class="flex min-h-48 items-center justify-center gap-3 p-6"
    role="status"
    aria-live="polite"
  >
    <span class="loading loading-spinner loading-md" aria-hidden="true"></span>
    <div>
      <h2 class="text-lg font-semibold">Loading {{ application.displayName }}</h2>
      <p class="text-sm text-base-content/70">
        Resolving the approved release and validating its contracts…
      </p>
    </div>
  </section>

  <div
    v-else
    class="contents"
    data-remote-state="ready"
    :data-mounted-application="application.applicationKey"
    :data-mounted-surface="application.surface.surfaceId"
    :data-mounted-release="application.release.releaseId"
  >
    <FullPageSurface
      :renderer="component"
      :mount="fullPageSurfaceProps(application, context, bridge)"
    />
  </div>
</template>
