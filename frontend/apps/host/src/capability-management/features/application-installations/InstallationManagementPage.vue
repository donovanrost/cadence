<script setup lang="ts">
import { computed, onBeforeUnmount, onErrorCaptured, ref, watch } from "vue";
import MissionApplicationsPage from "./MissionApplicationsPage.vue";
import SpacecraftApplicationsPage from "./SpacecraftApplicationsPage.vue";
import { admitSnapshot } from "./validation";
import type { ApplicationEvent, InstallationAction, LifecycleEvent } from "./contracts";

const props = defineProps<{
  scope: string;
  snapshot: unknown;
  execute: InstallationAction;
  refresh: () => Promise<void>;
}>();
const pending = ref(false);
const error = ref<string>();
const crashed = ref(false);
let disposed = false;
watch(
  () => props.snapshot,
  () => {
    crashed.value = false;
  },
);
onBeforeUnmount(() => {
  disposed = true;
});
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => admitSnapshot(props.snapshot, props.scope));
async function execute(event: LifecycleEvent, payload: ApplicationEvent) {
  if (pending.value || disposed || !admitted.value || crashed.value) return;
  pending.value = true;
  error.value = undefined;
  try {
    await props.execute(event, payload);
  } catch {
    if (!disposed) error.value = "The application action could not be completed. Try again.";
  } finally {
    if (!disposed) pending.value = false;
  }
}
</script>
<template>
  <section id="application-installation-management" :aria-busy="pending">
    <div
      v-if="crashed || !admitted"
      id="application-installation-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>Application management could not be loaded.</p>
      <button
        id="application-installation-retry"
        type="button"
        class="btn btn-sm mt-4"
        @click="refresh"
      >
        Retry
      </button>
    </div>
    <template v-else>
      <p
        v-if="error"
        id="application-installation-action-error"
        role="alert"
        class="mb-4 text-error"
      >
        {{ error }}
      </p>
      <MissionApplicationsPage
        v-if="admitted.scope === 'mission'"
        :presentation="admitted.data"
        :disabled="pending"
        @install="execute('install', $event)"
        @disable="execute('disable', $event)"
        @uninstall="execute('uninstall', $event)"
      />
      <SpacecraftApplicationsPage
        v-else
        :presentation="admitted.data"
        :disabled="pending"
        @install="execute('install', $event)"
        @disable="execute('disable', $event)"
        @uninstall="execute('uninstall', $event)"
      />
    </template>
  </section>
</template>
