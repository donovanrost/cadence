<script setup lang="ts">
import { computed } from "vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: string; dashboard_id?: string }>();
const valid = (value: unknown): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  new TextEncoder().encode(value).length <= 256 &&
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  !/[\u0000-\u001f\u007f]/.test(value);
const href = computed(() =>
  valid(props.mission_id) && valid(props.dashboard_id)
    ? `/missions/${encodeURIComponent(props.mission_id)}/ops/dashboards/${encodeURIComponent(props.dashboard_id)}/diagnostics`
    : null,
);
</script>
<template>
  <section class="p-6">
    <h1 class="text-xl font-semibold">Execution diagnostics</h1>
    <p class="mt-3 text-sm">
      Diagnostics are part of the Cadence Ops workspace. Opening the page starts a new inspection of
      the current publication, not a reconstruction of this viewer session.
    </p>
    <a v-if="href" id="diagnostics-open-workspace" class="btn btn-primary mt-4" :href="href"
      >Open in workspace</a
    >
    <p v-else role="status" class="mt-3 text-sm">The dashboard identity is unavailable.</p>
  </section>
</template>
