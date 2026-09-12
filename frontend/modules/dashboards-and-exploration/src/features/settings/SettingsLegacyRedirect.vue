<script setup lang="ts">
import { computed } from "vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: string; dashboard_id?: string }>();
const valid = (id: unknown): id is string =>
  typeof id === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(id);
const href = computed(() =>
  valid(props.mission_id) && valid(props.dashboard_id)
    ? "/missions/" +
      encodeURIComponent(props.mission_id) +
      "/ops/dashboards/" +
      encodeURIComponent(props.dashboard_id) +
      "/settings"
    : null,
);
</script>
<template>
  <section id="settings-legacy-redirect" class="space-y-3 p-6">
    <h1 class="text-xl font-semibold">Dashboard settings</h1>
    <p class="text-sm text-base-content/65">
      Settings now run in the Cadence workspace with current mission authorization.
    </p>
    <a v-if="href" id="settings-open-workspace" :href="href" class="btn btn-sm btn-primary"
      >Open dashboard settings</a
    >
    <p v-else role="status">
      The dashboard reference is unavailable. Open settings from the dashboard directory.
    </p>
  </section>
</template>
