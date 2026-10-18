<script setup lang="ts">
import { computed } from "vue";
import { spacecraftCommandingHref, type SpacecraftCommandingProps } from "./contracts";
const props = defineProps<SpacecraftCommandingProps>();
const href = computed(() => {
  try {
    return spacecraftCommandingHref(props.mission_id, props.spacecraft_id);
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="spacecraft-commanding-legacy" class="p-6 space-y-4">
    <h2 class="text-xl font-semibold">Command interpretation</h2>
    <p class="text-sm">Review the spacecraft's pinned profile and command target identities.</p>
    <a v-if="href" :href="href" class="btn btn-primary">Open spacecraft commanding</a>
    <p v-else role="status">The spacecraft identity is unavailable.</p>
  </section>
</template>
