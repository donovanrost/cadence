<script setup lang="ts">
import { computed } from "vue";
import type { HistoricalWorkflowProps } from "./contracts";
defineOptions({ inheritAttrs: false });
const props = defineProps<HistoricalWorkflowProps>();
const href = computed(() => {
  if (
    typeof props.mission_id !== "string" ||
    !props.mission_id ||
    props.mission_id.length > 240 ||
    !["reader", "manage"].includes(props.mode ?? "") ||
    !props.query ||
    typeof props.query !== "object" ||
    Array.isArray(props.query)
  )
    return null;
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(props.query)) {
    if (key !== "group" || typeof value !== "string" || !value || value.length > 240) return null;
    query.set(key, value);
  }
  return `/missions/${encodeURIComponent(props.mission_id)}/ops/data-operations${props.mode === "manage" ? "/manage" : ""}${query.size ? "?" + query : ""}`;
});
</script>
<template>
  <section id="history-legacy-redirect" class="space-y-3 p-6">
    <h1 class="text-xl font-semibold">Data Operations</h1>
    <p class="text-sm">
      Historical workflows are part of the Cadence Ops workspace. Open the page to inspect requests
      and act with your current permissions.
    </p>
    <a v-if="href" id="history-open-workspace" :href="href" class="btn btn-primary"
      >Open in workspace</a
    >
    <p v-else role="status" class="text-sm">The mission or group identity is unavailable.</p>
  </section>
</template>
