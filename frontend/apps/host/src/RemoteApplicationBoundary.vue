<script setup lang="ts">
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  HostBridge,
  HostContext,
} from "@cadence/plugin-sdk";
import { CButton } from "@cadence/ui";
import { onErrorCaptured, shallowRef, watch } from "vue";
import type { Component } from "vue";
import { loadFederatedApplication } from "./remote-loader";

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
const error = shallowRef<string>();
let loadGeneration = 0;

watch(() => props.application, loadApplication, { immediate: true });

onErrorCaptured((reason) => {
  component.value = undefined;
  error.value = messageFor(reason, "The application failed after it mounted.");
  return false;
});

async function loadApplication(): Promise<void> {
  const generation = ++loadGeneration;
  component.value = undefined;
  error.value = undefined;

  try {
    const remote = await loadFederatedApplication(props.application);
    if (generation !== loadGeneration) return;
    component.value = remote.default;
    emit("ready", remote.manifest);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = messageFor(reason, "The application remote could not be loaded.");
  }
}

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <section v-if="error" id="remote-error" class="remote-state remote-state--error">
    <p class="eyebrow">Remote unavailable</p>
    <h2>{{ application.displayName }} was contained.</h2>
    <p>{{ error }}</p>
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

  <component :is="component" v-else :bridge="bridge" :context="context" />
</template>
