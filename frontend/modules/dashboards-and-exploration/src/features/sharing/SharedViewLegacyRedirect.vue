<script setup lang="ts">
import { computed } from "vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: string; share_id?: string; snapshot_id?: string }>();
const valid = (v: unknown): v is string =>
  typeof v === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(v);
const href = computed(() => {
  const missionId = props.mission_id;
  const resourceId = props.share_id ?? props.snapshot_id;
  return valid(missionId) && valid(resourceId)
    ? "/missions/" +
        encodeURIComponent(missionId) +
        "/ops/" +
        (props.share_id ? "dashboard-shares/" : "dashboard-snapshots/") +
        encodeURIComponent(resourceId)
    : null;
});
</script>
<template>
  <section class="p-6">
    <h1 class="text-xl font-semibold">Shared dashboard</h1>
    <p class="mt-3 text-sm">This view is part of the Cadence Ops workspace.</p>
    <a v-if="href" id="shared-view-open-workspace" class="btn btn-primary mt-4" :href="href"
      >Open in workspace</a
    >
    <p v-else role="status" class="mt-3 text-sm">The view identity is unavailable.</p>
  </section>
</template>
