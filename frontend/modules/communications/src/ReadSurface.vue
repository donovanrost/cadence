<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import { admitReadSurface } from "./read-registry";
import type { ReadContext } from "./shared/read-contracts";
const props = defineProps<{
  surfaceId: string;
  version: number;
  payload: unknown;
  context: ReadContext;
}>();
defineEmits<{ retry: [] }>();
const rendererFailed = ref(false);
watch(
  () => [props.surfaceId, props.version, props.payload, props.context],
  () => (rendererFailed.value = false),
);
onErrorCaptured(() => {
  rendererFailed.value = true;
  return false;
});
const admitted = computed(() => {
  try {
    return admitReadSurface(props.surfaceId, props.version, props.payload, props.context);
  } catch {
    return null;
  }
});
</script>
<template>
  <section
    v-if="!admitted || rendererFailed"
    id="comms-read-unavailable"
    class="card border border-error/40 bg-base-200"
    role="alert"
  >
    <div class="card-body p-6">
      <h2 class="font-semibold">Communications view unavailable</h2>
      <p class="text-sm text-base-content/70">
        The response could not be displayed. Your current Cadence page remains available.
      </p>
      <button id="retry-comms-read" type="button" class="btn btn-sm" @click="$emit('retry')">
        Retry query
      </button>
    </div>
  </section>
  <component v-else :is="admitted.component" v-bind="admitted.props" />
</template>
