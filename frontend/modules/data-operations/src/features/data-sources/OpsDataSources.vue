<script setup lang="ts">
import { computed } from "vue";
import type { Page } from "./presentation-contract";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: Page }>();
const href = computed(() => {
  const p = props.page;
  const id = (value: unknown): value is string =>
    typeof value === "string" && value.length > 0 && new TextEncoder().encode(value).length <= 240;
  if (
    !p ||
    !id(p.mission_id) ||
    !["reader", "registration", "settings"].includes(p.mode) ||
    (p.data_source_id !== null && !id(p.data_source_id))
  )
    return null;
  const base = `/missions/${encodeURIComponent(p.mission_id)}/ops/data-sources`;
  if (p.mode === "registration")
    return p.data_source_id === null ? base + "/registration/new" : null;
  if (p.mode === "settings")
    return p.data_source_id ? `${base}/${encodeURIComponent(p.data_source_id)}/settings` : null;
  return p.data_source_id ? `${base}/${encodeURIComponent(p.data_source_id)}` : base;
});
</script>
<template>
  <section id="sources-legacy-redirect" class="space-y-3 p-6">
    <h2 class="text-xl font-semibold">Data Sources</h2>
    <p class="text-sm">
      Source configuration, observations and backend operations are part of the Cadence Ops
      workspace.
    </p>
    <a v-if="href" id="sources-open-workspace" :href="href" class="btn btn-primary"
      >Open in workspace</a
    >
    <p v-else role="status" class="text-sm">The mission or source identity is unavailable.</p>
  </section>
</template>
