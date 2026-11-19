<script setup lang="ts">
import { shallowRef, watch } from "vue";
import { formatClock, ApCallout } from "@/ui";
import { useConnection } from "@/live/index.ts";
import { FLEET_POLL_OFFLINE_S } from "@/features/fleet/index.ts";

/**
 * Says how fresh the screen is when the socket isn't live (ux review fix 2): a real drop names
 * the time it happened; a link that never came up says so. Both state the polling interval.
 */
const connection = useConnection();
const lostAt = shallowRef<Date | null>(null);
watch(
  connection,
  (now, before) => {
    if (now === "live") lostAt.value = null;
    else if (before === "live") lostAt.value = new Date();
  },
  { immediate: true },
);
</script>

<template>
  <ApCallout v-if="connection !== 'live'" tone="stale" class="flex-none">
    <template v-if="lostAt">
      Live updates lost at {{ formatClock(lostAt) }}Z. Values refresh every
      {{ FLEET_POLL_OFFLINE_S }} s until the link is back.
    </template>
    <template v-else>
      Live updates aren't connected yet. Values refresh every {{ FLEET_POLL_OFFLINE_S }} s.
    </template>
  </ApCallout>
</template>
