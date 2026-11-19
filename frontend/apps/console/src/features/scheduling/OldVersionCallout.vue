<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { ApButton, ApCallout, useNow } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { oldVersionLine } from "./plan-history.ts";

/** U73: an older version (`?version=N`) is read-only; this says which and opens the current one. */
const props = defineProps<{ plan: PlanDetail; latest: number }>();
const route = useRoute();
const now = useNow();
const line = computed(() => oldVersionLine(props.plan, props.latest, now.value));
const current = computed(() => {
  const { version: _drop, ...rest } = route.query;
  return { name: "ops.contacts.plan" as const, query: rest };
});
</script>

<template>
  <ApCallout tone="info">
    {{ line }}
    <template #action
      ><ApButton size="compact" :to="current">Review current version</ApButton></template
    >
  </ApCallout>
</template>
