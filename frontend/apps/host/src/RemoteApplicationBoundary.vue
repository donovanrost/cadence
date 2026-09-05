<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { CButton } from "@cadence/ui";
import { onBeforeUnmount, onErrorCaptured, shallowRef, watch } from "vue";
import type { Component } from "vue";
import FullPageSurface from "./FullPageSurface.vue";
import { createHostContributionBootstrap } from "./first-party-composition";
import { loadFederatedApplication } from "./remote-loader";
import { fullPageSurfaceProps } from "@cadence/plugin-sdk";

const props = defineProps<{
  application: CatalogApplication;
  bridge: HostBridge;
  context: HostContext;
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

onErrorCaptured((_reason) => {
  loadGeneration += 1;
  loadController?.abort(new Error("Remote application mount failed."));
  component.value = undefined;
  error.value = failureFor("The approved application failed after mounting.");
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
    error.value = failureFor("The approved application release could not be loaded.");
  } finally {
    if (loadController === controller) loadController = undefined;
  }
}

function failureFor(message: string): { message: string; referenceId: string } {
  return { message, referenceId: crypto.randomUUID() };
}
</script>

<template>
  <section v-if="error" id="remote-error" class="remote-state remote-state--error">
    <p class="eyebrow">Remote unavailable</p>
    <h2>{{ application.displayName }} was contained.</h2>
    <p id="remote-error-message">{{ error.message }}</p>
    <p id="remote-error-reference">Reference ID: {{ error.referenceId }}</p>
    <p class="remote-state__hint">
      The Cadence shell, session, navigation, and other applications remain available.
    </p>
    <CButton id="retry-remote" @click="$emit('retry')">Retry approved release</CButton>
  </section>

  <section v-else-if="!component" id="remote-loading" class="remote-state">
    <div class="loader-grid" aria-hidden="true">
      <span v-for="cell in 12" :key="cell"></span>
    </div>
    <div>
      <p class="eyebrow">Resolving trusted renderer</p>
      <h2>Mounting {{ application.displayName }}</h2>
      <p>Resolving {{ application.release.releaseId }} and validating its contracts…</p>
    </div>
  </section>

  <FullPageSurface
    v-else
    :renderer="component"
    :mount="fullPageSurfaceProps(application, context, bridge)"
  />
</template>
