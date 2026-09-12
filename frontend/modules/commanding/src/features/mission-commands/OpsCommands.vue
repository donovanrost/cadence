<script setup lang="ts">
import { computed } from "vue";
import { monitorHref, readMonitorQuery } from "./monitor-query";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: string; query?: unknown }>();
const href = computed(() => {
  try {
    return monitorHref(props.mission_id ?? "", readMonitorQuery(props.query));
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="commands-legacy-redirect" class="p-6">
    <h1 class="text-xl font-semibold">Commands</h1>
    <p class="mt-3 text-sm">
      Command monitoring is part of the Cadence Ops workspace. Open the page to read the current
      mission projection with your current permissions.
    </p>
    <a v-if="href" id="commands-open-workspace" class="btn btn-primary mt-4" :href="href"
      >Open in workspace</a
    >
    <p v-else role="status" class="mt-3 text-sm">The mission or query identity is unavailable.</p>
  </section>
</template>
