<script setup lang="ts">
import { computed } from "vue";
import { timelineHref, type TimelineQuery } from "./contracts";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id: string; query?: Partial<TimelineQuery> }>();
const href = computed(() => {
  try {
    return timelineHref(props.mission_id, props.query ?? {});
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="timeline-destination" class="card space-y-4 p-6">
    <h2 class="text-lg font-semibold">Mission timeline</h2>
    <p>Open the workspace timeline to filter mission events and inspect their evidence.</p>
    <a v-if="href" :href="href" class="btn btn-primary btn-sm">Open mission timeline</a>
    <p v-else role="alert">The mission destination is unavailable.</p>
  </section>
</template>
