<script setup lang="ts">
import { computed } from "vue";
import { queryKeys, validQueryText as validText } from "./query";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: string; query?: unknown }>();
const href = computed(() => {
  if (
    !validText(props.mission_id) ||
    !props.mission_id ||
    !props.query ||
    typeof props.query !== "object" ||
    Array.isArray(props.query)
  )
    return null;
  const entries = Object.entries(props.query);
  if (
    entries.length > queryKeys.length + 1 ||
    entries.some(
      ([key, value]) =>
        !(queryKeys.includes(key as (typeof queryKeys)[number]) || key === "data_view") ||
        !validText(value),
    )
  )
    return null;
  const search = new URLSearchParams(entries as [string, string][]);
  return `/missions/${encodeURIComponent(props.mission_id)}/ops/explore${search.size ? `?${search}` : ""}`;
});
</script>
<template>
  <section id="exploration-legacy-redirect" class="p-6">
    <h1 class="text-xl font-semibold">Explore</h1>
    <p class="mt-3 text-sm">
      Exploration is part of the Cadence Ops workspace. Open the page to run this query with your
      current permissions.
    </p>
    <a v-if="href" id="exploration-open-workspace" class="btn btn-primary mt-4" :href="href"
      >Open in workspace</a
    >
    <p v-else role="status" class="mt-3 text-sm">The mission or query identity is unavailable.</p>
  </section>
</template>
