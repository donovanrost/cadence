<script setup lang="ts">
import { ApButton, ApEmptyState, ApPanel } from "@/ui";

/**
 * A4 · Passes in the next 2 h. The pass-window read (ops plan M7) doesn't exist yet, so the panel
 * keeps its place with an honest unavailable state (U10) instead of an empty schedule.
 */
</script>

<template>
  <ApPanel index="A4" title="Passes · next 2 h" pane flush>
    <template #meta>
      <RouterLink
        :to="{ name: 'ops.contacts' }"
        class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
        >Open contacts →</RouterLink
      >
    </template>
    <ApEmptyState
      state="off"
      headline="Pass schedule not available"
      sentence="Ground-station passes aren't connected to this console yet. Contacts lists what is booked."
    >
      <ApButton size="compact" :to="{ name: 'ops.contacts' }">Open contacts</ApButton>
    </ApEmptyState>
  </ApPanel>
</template>
