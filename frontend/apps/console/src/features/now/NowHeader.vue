<script setup lang="ts">
import { computed } from "vue";
import { formatCount, formatDuration, useNow, ApPageHeader } from "@/ui";
import type { Fleet } from "@/features/fleet/index.ts";

/** Header: computed situation h1 + freshness meta. Unknown parts are omitted, never guessed. */
const props = defineProps<{ missionName: string; headline: string; fleet: Fleet | null }>();
const now = useNow();

const meta = computed(() => {
  const fleet = props.fleet;
  if (!fleet) return "";
  const parts = [`TLM fresh ${formatCount(fleet.counts.fresh)}/${formatCount(fleet.counts.total)}`];
  if (fleet.last_received_at) {
    const age = (now.value.getTime() - Date.parse(fleet.last_received_at)) / 1000;
    parts.push(`last pkt ${formatDuration(age)}`);
  }
  return parts.join(" · ");
});
</script>

<template>
  <ApPageHeader :label="`${missionName} · constellation status`" :title="headline">
    <p v-if="meta" class="m-0 font-mono text-sm text-text-3 uppercase">{{ meta }}</p>
  </ApPageHeader>
</template>
