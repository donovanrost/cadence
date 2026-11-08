<script setup lang="ts">
import { ApEmptyState, ApPanel } from "@/ui";

/** B2 · Event log. The console events read is requested from api; until then, unavailable (U10). */
</script>

<template>
  <ApPanel index="B2" title="Event log" pane flush>
    <template #meta>
      <RouterLink :to="{ name: 'ops.timeline' }" class="text-text-3 no-underline hover:text-readout"
        >Full timeline →</RouterLink
      >
    </template>
    <ApEmptyState
      state="off"
      headline="Event log not available"
      sentence="Spacecraft events aren't connected to this console yet."
    />
  </ApPanel>
</template>
