<script setup lang="ts">
import { computed } from "vue";
import { formatHourMinute, useNow } from "@/ui";
import CockpitStatus from "./CockpitStatus.vue";

/**
 * The viewer's phone status bar (ux Dashboards.md §Phone, 45d26151f): a takeover has no tab bar
 * (and so no alarm count), so live fleet health stays on screen here, never inside ⋯. 48px of
 * chrome above the home indicator: health on the left, UTC on the right. The viewer leaves the
 * same height free under the board, so the last widget isn't hidden under it.
 */
const now = useNow();
const utc = computed(() => formatHourMinute(now.value));
</script>

<template>
  <section
    aria-label="Fleet health"
    class="fixed inset-x-0 bottom-0 z-30 flex h-[calc(48px+env(safe-area-inset-bottom))] items-start border-t border-hairline bg-chrome px-4 pb-[env(safe-area-inset-bottom)] font-mono text-md"
  >
    <span class="flex h-12 min-w-0 items-center"><CockpitStatus words /></span>
    <span class="ml-auto flex h-12 flex-none items-center gap-[0.6em]"
      ><span class="text-text-4">UTC</span
      ><time :datetime="now.toISOString()">{{ utc }}</time></span
    >
  </section>
</template>
